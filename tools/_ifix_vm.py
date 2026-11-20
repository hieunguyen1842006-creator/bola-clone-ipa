"""Local bytecode test interpreter; does not run or emulate the game renderer."""
import struct
import math

class Obj(dict):
    def __bool__(self):
        return True

TRACE = None

def execute(patch, method_id, arguments, native, arities):
    code = patch['methods'][method_id]['instructions']
    stack, locals_, pc = [], {}, 0
    for _ in range(10000):
        instruction = code[pc]
        op, value = instruction['op'], instruction['operand']
        if TRACE is not None:
            TRACE.append((pc, op, len(stack)))
        next_pc = pc + 1
        try:
            if op in {'StackSpace', 'Nop'}: pass
            elif op == 'Ldarg': stack.append(arguments[value])
            elif op == 'Ldnull': stack.append(None)
            elif op == 'Ldtype': stack.append(patch['extern_types'][value].split(',')[0])
            elif op in {'Unbox_Any', 'Castclass'}: pass
            elif op == 'Isinst':
                stack.append(native.isinst(patch['extern_types'][value], stack.pop()))
            elif op == 'Box':
                stack.append(native.box(patch['extern_types'][value], stack.pop()))
            elif op == 'Ldsfld': stack.append(native.static_field(patch['fields'][value]))
            elif op == 'Dup': stack.append(stack[-1])
            elif op == 'Pop': stack.pop()
            elif op == 'Newarr': stack.append([None] * stack.pop())
            elif op in {'Stelem_Ref','Stelem_Any'}:
                item, index, array = stack.pop(), stack.pop(), stack.pop()
                array[index] = item
            elif op == 'Ldelem_Ref':
                index, array = stack.pop(), stack.pop()
                stack.append(array[index])
            elif op == 'Ldlen': stack.append(len(stack.pop()))
            elif op == 'Ldloc': stack.append(locals_[value])
            elif op == 'Ldloca':
                if value not in locals_: locals_[value] = Obj()
                stack.append(locals_[value])
            elif op == 'Stloc': locals_[value] = stack.pop()
            elif op == 'Ldc_I4': stack.append(value)
            elif op == 'Ldc_R4': stack.append(struct.unpack('<f', struct.pack('<i', value))[0])
            elif op == 'Ldstr': stack.append(patch['intern_strings'][value]['value'])
            elif op == 'Initobj': stack.pop().clear()
            elif op == 'Ldfld':
                obj = stack.pop()
                field = patch['fields'][value]
                numeric = field.get('field_type', '').split(',')[0] in {
                    'System.Int32', 'System.UInt32', 'System.Single', 'System.Boolean'}
                default = 0 if not field['is_new'] or numeric else None
                stack.append(obj.get(field['name'], default))
            elif op == 'Stfld':
                field_value, obj = stack.pop(), stack.pop()
                obj[patch['fields'][value]['name']] = field_value
            elif op.startswith('Stind_'):
                field_value, target = stack.pop(), stack.pop()
                target['value'] = field_value
            elif op.startswith('Ldind_'):
                stack.append(stack.pop()['value'])
            elif op == 'Conv_R4': stack.append(float(stack.pop()))
            elif op in {'Conv_I4', 'Conv_I8'}: stack.append(int(stack.pop()))
            elif op == 'Conv_U4': stack.append(int(stack.pop()) & 0xffffffff)
            elif op == 'Ceq':
                right, left = stack.pop(), stack.pop()
                references = isinstance(left, (dict, list)) or isinstance(right, (dict, list))
                stack.append(int((left is right) if references else left == right))
            elif op in {'Cgt', 'Cgt_Un', 'Clt', 'Clt_Un'}:
                right, left = stack.pop(), stack.pop()
                if op == 'Cgt': v = left > right
                elif op == 'Cgt_Un': v = left > right
                elif op == 'Clt': v = left < right
                else: v = left < right
                stack.append(int(v))
            elif op in {'And','Or','Xor'}:
                right,left=stack.pop(),stack.pop()
                stack.append(left & right if op=='And' else left | right if op=='Or' else left ^ right)
            elif op in {'Rem', 'Rem_Un'}:
                right, left = stack.pop(), stack.pop()
                stack.append(left % right)
            elif op == 'Div_Un':
                right, left = stack.pop(), stack.pop()
                stack.append(left // right)
            elif op in {'Mul', 'Mul_Ovf', 'Div', 'Sub', 'Add'}:
                right, left = stack.pop(), stack.pop()
                stack.append(left * right if op.startswith('Mul') else left / right if op == 'Div'
                             else left + right if op == 'Add' else left - right)
            elif op in {'CallExtern', 'Call', 'Newobj'}:
                count, index = value >> 16, value & 65535
                args = stack[-count:] if count else []
                if count: del stack[-count:]
                if op == 'Newobj':
                    result = native.call(patch['extern_methods'][index], args)
                    returns = 1
                elif op == 'Call':
                    result = execute(patch, index, args, native, arities)
                    returns = next(i['operand'] for i in patch['methods'][index]['instructions'] if i['op'] == 'Ret')
                else:
                    result = native.call(patch['extern_methods'][index], args)
                    returns = arities[index]
                if returns: stack.append(result)
            elif op == 'Br': next_pc = pc + value
            elif op in {'Brtrue', 'Brfalse'}:
                item = stack.pop()
                # IFix Brtrue/Brfalse test reference nullness, not Python
                # container/string emptiness (VirtualMachine.cs:1092/1187).
                truth = bool(item) if isinstance(item, (int, float)) else item is not None
                if truth == (op == 'Brtrue'): next_pc = pc + value
            elif op in {'Beq', 'Bne_Un', 'Blt', 'Bgt', 'Ble', 'Bge'}:
                right, left = stack.pop(), stack.pop()
                # Evaluate only the requested relation. Eagerly constructing
                # every comparison raised TypeError for a valid object/null
                # Beq. Managed reference equality is identity, not dict/list
                # content equality in the host-side object representation.
                if op in {'Beq', 'Bne_Un'}:
                    references = isinstance(left, (dict, list)) or isinstance(right, (dict, list))
                    equal = (left is right) if references else left == right
                    condition = equal if op == 'Beq' else not equal
                elif op == 'Blt': condition = left < right
                elif op == 'Bgt': condition = left > right
                elif op == 'Ble': condition = left <= right
                else: condition = left >= right
                if condition: next_pc = pc + value
            elif op == 'Throw':
                raise stack.pop()
            elif op == 'Ret':
                result = stack.pop() if value else None
                assert not stack, f'Ret at pc {pc} leaves {len(stack)} stack slots in method {method_id}'
                return result
            else: raise AssertionError(f'Unsupported VM fixture opcode {op}')
        except Exception as error:
            # Model IFix catch-only semantics; no finally/filter support is implied.
            handlers=patch['methods'][method_id].get('exception_handlers',[])
            match=next((h for h in handlers if h['handler_type']==0
                        and h['catch_type_id']==-1 and h['try_start']<=pc<h['try_end']),None)
            if match is None:raise
            stack[:]=[error]
            next_pc=match['handler_start']
        pc = next_pc
    raise AssertionError('Unexpected loop in gesture bytecode')
