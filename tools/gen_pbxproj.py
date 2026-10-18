#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Sinh BolaClone.xcodeproj/project.pbxproj (khong can Xcode/macOS).

Chay: python tools/gen_pbxproj.py
Kiem tra lai: python tools/check_pbxproj.py
"""
from __future__ import annotations

import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BS = chr(92)          # backslash (tranh heredoc/escape)


def oid(seed: str) -> str:
    return hashlib.md5(seed.encode()).hexdigest()[:24].upper()


def main() -> int:
    swift_files = []
    for root, _dirs, files in os.walk(os.path.join(ROOT, "Sources")):
        for f in files:
            if f.endswith(".swift"):
                rel = os.path.relpath(os.path.join(root, f), ROOT).replace(BS, "/")
                swift_files.append(rel)
    swift_files.sort()

    # Vendor3105: Swift + ObjC/C (MHA bridge) — chỉ dựng trong Xcode, không vào SwiftPM.
    vendor_dir = os.path.join(ROOT, "Vendor3105")
    vendor_sources = []
    vendor_headers = []
    if os.path.isdir(vendor_dir):
        for root, _d, files in os.walk(vendor_dir):
            for f in sorted(files):
                rel = os.path.relpath(os.path.join(root, f), ROOT).replace(BS, "/")
                if f.endswith((".swift", ".m", ".c")):
                    vendor_sources.append(rel)
                elif f.endswith(".h"):
                    vendor_headers.append(rel)
        vendor_sources.sort()
        vendor_headers.sort()

    def vendor_path(p: str) -> str:
        return p[len("Vendor3105/"):]

    def file_type(p: str) -> str:
        if p.endswith(".swift"): return "sourcecode.swift"
        if p.endswith(".m"): return "sourcecode.c.objc"
        if p.endswith(".c"): return "sourcecode.c.c"
        if p.endswith(".h"): return "sourcecode.c.h"
        return "text"

    all_sources = swift_files + vendor_sources

    group_of = lambda p: "/".join(p.split("/")[:-1])
    groups = sorted({group_of(p) for p in swift_files})

    res_files = ["Resources/Assets.xcassets", "Resources/bola_silence.wav",
                 "Resources/BolaminhducMenu.bytes"]
    ref_key = {"Resources/Assets.xcassets": "fr-Assets", "Resources/bola_silence.wav": "fr-Wav",
               "Resources/BolaminhducMenu.bytes": "fr-Patch"}

    L: list[str] = []
    w = L.append
    w("// !$*UTF8*$!")
    w("{")
    w("\tarchiveVersion = 1;")
    w("\tclasses = {};")
    w("\tobjectVersion = 56;")
    w("\tobjects = {")
    w("")

    # ---- PBXBuildFile
    w("/* Begin PBXBuildFile section */")
    for p in all_sources:
        w("\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
          % (oid("bf" + p), os.path.basename(p), oid("fr" + p), os.path.basename(p)))
    for p in res_files:
        w("\t\t%s /* %s in Resources */ = {isa = PBXBuildFile; fileRef = %s /* %s */; };"
          % (oid("bf" + p), os.path.basename(p), oid(ref_key[p]), os.path.basename(p)))
    w("/* End PBXBuildFile section */")
    w("")

    # ---- PBXFileReference
    w("/* Begin PBXFileReference section */")
    w("\t\t%s /* BolaClone.app */ = {isa = PBXFileReference; explicitFileType = "
      "wrapper.application; includeInIndex = 0; path = BolaClone.app; "
      "sourceTree = BUILT_PRODUCTS_DIR; };" % oid("product"))
    for p in swift_files:
        w("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; "
          "path = %s; sourceTree = \"<group>\"; };"
          % (oid("fr" + p), os.path.basename(p), file_type(p), os.path.basename(p)))
    for p in vendor_sources + vendor_headers:
        w("\t\t%s /* %s */ = {isa = PBXFileReference; lastKnownFileType = %s; "
          "path = %s; sourceTree = \"<group>\"; };"
          % (oid("fr" + p), os.path.basename(p), file_type(p), vendor_path(p)))
    w("\t\t%s /* Assets.xcassets */ = {isa = PBXFileReference; lastKnownFileType = "
      "folder.assetcatalog; path = Assets.xcassets; sourceTree = \"<group>\"; };"
      % oid("fr-Assets"))
    w("\t\t%s /* bola_silence.wav */ = {isa = PBXFileReference; lastKnownFileType = audio.wav; "
      "path = bola_silence.wav; sourceTree = \"<group>\"; };" % oid("fr-Wav"))
    w("\t\t%s /* BolaminhducMenu.bytes */ = {isa = PBXFileReference; lastKnownFileType = "
      "file; path = BolaminhducMenu.bytes; sourceTree = \"<group>\"; };" % oid("fr-Patch"))
    w("\t\t%s /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; "
      "path = Info.plist; sourceTree = \"<group>\"; };" % oid("fr-Info"))
    w("/* End PBXFileReference section */")
    w("")

    # ---- Frameworks
    w("/* Begin PBXFrameworksBuildPhase section */")
    w("\t\t%s /* Frameworks */ = {" % oid("fwphase"))
    w("\t\t\tisa = PBXFrameworksBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (\n\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXFrameworksBuildPhase section */")
    w("")

    # ---- Groups
    w("/* Begin PBXGroup section */")
    w("\t\t%s = {" % oid("grp-root"))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* Sources */," % oid("grp-Sources"))
    if vendor_sources or vendor_headers:
        w("\t\t\t\t%s /* Vendor3105 */," % oid("grp-Vendor3105"))
    w("\t\t\t\t%s /* Resources */," % oid("grp-Resources"))
    w("\t\t\t\t%s /* Products */," % oid("grp-Products"))
    w("\t\t\t);")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w("\t\t%s /* Sources */ = {" % oid("grp-Sources"))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    for g in groups:
        w("\t\t\t\t%s /* %s */," % (oid("grp-" + g), g.split("/")[-1]))
    w("\t\t\t);")
    w("\t\t\tpath = Sources;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    for g in groups:
        kids = [p for p in swift_files if group_of(p) == g]
        w("\t\t%s /* %s */ = {" % (oid("grp-" + g), g.split("/")[-1]))
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for p in kids:
            w("\t\t\t\t%s /* %s */," % (oid("fr" + p), os.path.basename(p)))
        w("\t\t\t);")
        w("\t\t\tpath = %s;" % g.split("/")[-1])
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")
    if vendor_sources or vendor_headers:
        w("\t\t%s /* Vendor3105 */ = {" % oid("grp-Vendor3105"))
        w("\t\t\tisa = PBXGroup;")
        w("\t\t\tchildren = (")
        for p in vendor_sources + vendor_headers:
            w("\t\t\t\t%s /* %s */," % (oid("fr" + p), os.path.basename(p)))
        w("\t\t\t);")
        w("\t\t\tpath = Vendor3105;")
        w("\t\t\tsourceTree = \"<group>\";")
        w("\t\t};")
    w("\t\t%s /* Resources */ = {" % oid("grp-Resources"))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* Assets.xcassets */," % oid("fr-Assets"))
    w("\t\t\t\t%s /* bola_silence.wav */," % oid("fr-Wav"))
    w("\t\t\t\t%s /* BolaminhducMenu.bytes */," % oid("fr-Patch"))
    w("\t\t\t\t%s /* Info.plist */," % oid("fr-Info"))
    w("\t\t\t);")
    w("\t\t\tpath = Resources;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w("\t\t%s /* Products */ = {" % oid("grp-Products"))
    w("\t\t\tisa = PBXGroup;")
    w("\t\t\tchildren = (")
    w("\t\t\t\t%s /* BolaClone.app */," % oid("product"))
    w("\t\t\t);")
    w("\t\t\tname = Products;")
    w("\t\t\tsourceTree = \"<group>\";")
    w("\t\t};")
    w("/* End PBXGroup section */")
    w("")

    # ---- NativeTarget
    w("/* Begin PBXNativeTarget section */")
    w("\t\t%s /* BolaClone */ = {" % oid("target"))
    w("\t\t\tisa = PBXNativeTarget;")
    w("\t\t\tbuildConfigurationList = %s;" % oid("cfglist-target"))
    w("\t\t\tbuildPhases = (")
    w("\t\t\t\t%s /* Sources */," % oid("srcphase"))
    w("\t\t\t\t%s /* Frameworks */," % oid("fwphase"))
    w("\t\t\t\t%s /* Resources */," % oid("resphase"))
    w("\t\t\t);")
    w("\t\t\tbuildRules = (\n\t\t\t);")
    w("\t\t\tdependencies = (\n\t\t\t);")
    w("\t\t\tname = BolaClone;")
    w("\t\t\tproductName = BolaClone;")
    w("\t\t\tproductReference = %s /* BolaClone.app */;" % oid("product"))
    w("\t\t\tproductType = \"com.apple.product-type.application\";")
    w("\t\t};")
    w("/* End PBXNativeTarget section */")
    w("")

    # ---- Project
    w("/* Begin PBXProject section */")
    w("\t\t%s /* Project object */ = {" % oid("project"))
    w("\t\t\tisa = PBXProject;")
    w("\t\t\tattributes = {")
    w("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    w("\t\t\t\tLastSwiftUpdateCheck = 1600;")
    w("\t\t\t\tLastUpgradeCheck = 1600;")
    w("\t\t\t\tTargetAttributes = {")
    w("\t\t\t\t\t%s = { CreatedOnToolsVersion = 16.0; };" % oid("target"))
    w("\t\t\t\t};")
    w("\t\t\t};")
    w("\t\t\tbuildConfigurationList = %s;" % oid("cfglist-project"))
    w("\t\t\tcompatibilityVersion = \"Xcode 15.0\";")
    w("\t\t\tdevelopmentRegion = en;")
    w("\t\t\thasScannedForEncodings = 0;")
    w("\t\t\tknownRegions = (en, Base);")
    w("\t\t\tmainGroup = %s;" % oid("grp-root"))
    w("\t\t\tproductRefGroup = %s /* Products */;" % oid("grp-Products"))
    w("\t\t\tprojectDirPath = \"\";")
    w("\t\t\tprojectRoot = \"\";")
    w("\t\t\ttargets = (")
    w("\t\t\t\t%s /* BolaClone */," % oid("target"))
    w("\t\t\t);")
    w("\t\t};")
    w("/* End PBXProject section */")
    w("")

    # ---- Resources phase
    w("/* Begin PBXResourcesBuildPhase section */")
    w("\t\t%s /* Resources */ = {" % oid("resphase"))
    w("\t\t\tisa = PBXResourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for p in res_files:
        w("\t\t\t\t%s /* %s in Resources */," % (oid("bf" + p), os.path.basename(p)))
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXResourcesBuildPhase section */")
    w("")

    # ---- Sources phase
    w("/* Begin PBXSourcesBuildPhase section */")
    w("\t\t%s /* Sources */ = {" % oid("srcphase"))
    w("\t\t\tisa = PBXSourcesBuildPhase;")
    w("\t\t\tbuildActionMask = 2147483647;")
    w("\t\t\tfiles = (")
    for p in all_sources:
        w("\t\t\t\t%s /* %s in Sources */," % (oid("bf" + p), os.path.basename(p)))
    w("\t\t\t);")
    w("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    w("\t\t};")
    w("/* End PBXSourcesBuildPhase section */")
    w("")

    # ---- Build configurations
    def cfg_block(seed: str, name: str, settings: dict) -> None:
        w("\t\t%s /* %s */ = {" % (oid(seed), name))
        w("\t\t\tisa = XCBuildConfiguration;")
        w("\t\t\tbuildSettings = {")
        for k in sorted(settings):
            w("\t\t\t\t%s = %s;" % (k, settings[k]))
        w("\t\t\t};")
        w("\t\t\tname = %s;" % name)
        w("\t\t};")

    common = {
        "ALWAYS_SEARCH_USER_PATHS": "NO",
        "CLANG_ENABLE_MODULES": "YES",
        "CLANG_ENABLE_OBJC_ARC": "YES",
        "ENABLE_BITCODE": "NO",
        "GCC_C_LANGUAGE_STANDARD": "gnu17",
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "SDKROOT": "iphoneos",
        "SWIFT_VERSION": "5.9",
        "TARGETED_DEVICE_FAMILY": "\"1,2\"",
    }
    tgt = {
        "CODE_SIGN_STYLE": "Automatic",
        "CURRENT_PROJECT_VERSION": "1",
        "GENERATE_INFOPLIST_FILE": "NO",
        "INFOPLIST_FILE": "Resources/Info.plist",
        "LD_RUNPATH_SEARCH_PATHS": "(\"@executable_path/Frameworks\")",
        "MARKETING_VERSION": "1.0.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.apple.mobile.MobileHouseArrest",
        "PRODUCT_NAME": "BolaClone",
        "SWIFT_OBJC_BRIDGING_HEADER": "Vendor3105/BolaClone-Bridging-Header.h",
        "SWIFT_EMIT_LOC_STRINGS": "NO",
        "SWIFT_VERSION": "5.9",
        "TARGETED_DEVICE_FAMILY": "\"1,2\"",
    }
    tgt_release = dict(tgt)

    w("/* Begin XCBuildConfiguration section */")
    cfg_block("cfg-proj-debug", "Debug", dict(common, **{"ONLY_ACTIVE_ARCH": "YES",
                                                        "SWIFT_OPTIMIZATION_LEVEL": "\"-Onone\""}))
    cfg_block("cfg-proj-release", "Release", dict(common, **{"SWIFT_OPTIMIZATION_LEVEL": "\"-O\""}))
    cfg_block("cfg-tgt-debug", "Debug", dict(tgt, **{"SWIFT_OPTIMIZATION_LEVEL": "\"-Onone\"",
                                                     "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG"}))
    cfg_block("cfg-tgt-release", "Release", dict(tgt_release, **{"SWIFT_OPTIMIZATION_LEVEL": "\"-O\""}))
    w("/* End XCBuildConfiguration section */")
    w("")

    def cfg_list(seed: str, name: str) -> None:
        w("\t\t%s /* Build configuration list for %s */ = {" % (oid(seed), name))
        w("\t\t\tisa = XCConfigurationList;")
        w("\t\t\tbuildConfigurations = (")
        w("\t\t\t\t%s /* Debug */," % oid("cfg-" + ("proj" if "project" in seed else "tgt") + "-debug"))
        w("\t\t\t\t%s /* Release */," % oid("cfg-" + ("proj" if "project" in seed else "tgt") + "-release"))
        w("\t\t\t);")
        w("\t\t\tdefaultConfigurationIsVisible = 0;")
        w("\t\t\tdefaultConfigurationName = Release;")
        w("\t\t};")

    w("/* Begin XCConfigurationList section */")
    cfg_list("cfglist-project", "PBXProject")
    cfg_list("cfglist-target", "PBXNativeTarget")
    w("/* End XCConfigurationList section */")
    w("")
    w("\t};")
    w("\trootObject = %s /* Project object */;" % oid("project"))
    w("}")

    out_dir = os.path.join(ROOT, "BolaClone.xcodeproj")
    os.makedirs(out_dir, exist_ok=True)
    open(os.path.join(out_dir, "project.pbxproj"), "w", encoding="utf-8").write("\n".join(L) + "\n")
    print("pbxproj: %d dong | %d swift | %d resource" % (len(L), len(swift_files), len(res_files)))
    for p in swift_files:
        print("   ", p)
    return 0


if __name__ == "__main__":
    sys.exit(main())
