import tools.merge_menu as M

pf, _, _, _ = M.load('HeroSkin_2_v140.bytes', 'HeroSkin_2')
ins3 = pf['blocks'][3]['instrs']
print(f"VM 3 len: {len(ins3)}")
print(f"strings count: {len(pf['strings'])}")
print(f"last 2 strings: {pf['strings'][-2:]}")
print(f"pc 2444: {hex(ins3[2444])} arg={ins3[2445]}")
print(f"pc 2446: {hex(ins3[2446])} arg={ins3[2447]}")
print(f"pc 2688: {hex(ins3[2688])} arg={ins3[2689]}")
