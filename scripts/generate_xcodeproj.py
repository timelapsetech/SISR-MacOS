#!/usr/bin/env python3
"""Generate a minimal SISR.xcodeproj that depends on Packages/SISRKit."""

from __future__ import annotations

import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APP = ROOT / "SISR"
PROJECT = ROOT / "SISR.xcodeproj"


def uid() -> str:
    return uuid.uuid4().hex[:24].upper()


def main() -> None:
    swift_files = sorted(APP.rglob("*.swift"))

    ids = {
        "project": uid(),
        "target": uid(),
        "sources": uid(),
        "resources": uid(),
        "frameworks": uid(),
        "proj_configs": uid(),
        "tgt_configs": uid(),
        "dbg_proj": uid(),
        "rel_proj": uid(),
        "dbg_tgt": uid(),
        "rel_tgt": uid(),
        "main_group": uid(),
        "app_group": uid(),
        "products": uid(),
        "product": uid(),
        "assets": uid(),
        "assets_build": uid(),
        "privacy": uid(),
        "privacy_build": uid(),
        "info": uid(),
        "entitlements": uid(),
        "package": uid(),
        "product_dep": uid(),
        "package_build": uid(),
    }

    file_refs: list[tuple[str, str, Path]] = []
    for path in swift_files:
        file_refs.append((uid(), uid(), path))

    o: list[str] = []
    a = o.append
    a("// !$*UTF8*$!")
    a("{")
    a("\tarchiveVersion = 1;")
    a("\tclasses = {};")
    a("\tobjectVersion = 56;")
    a("\tobjects = {")

    a("/* Begin PBXBuildFile section */")
    for fr, br, path in file_refs:
        a(f"\t\t{br} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {path.name} */; }};")
    a(f"\t\t{ids['assets_build']} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {ids['assets']} /* Assets.xcassets */; }};")
    a(f"\t\t{ids['privacy_build']} /* PrivacyInfo.xcprivacy in Resources */ = {{isa = PBXBuildFile; fileRef = {ids['privacy']} /* PrivacyInfo.xcprivacy */; }};")
    a(f"\t\t{ids['package_build']} /* SISRKit in Frameworks */ = {{isa = PBXBuildFile; productRef = {ids['product_dep']} /* SISRKit */; }};")
    a("/* End PBXBuildFile section */")

    a("/* Begin PBXFileReference section */")
    a(f"\t\t{ids['product']} /* SISR.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SISR.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
    for fr, _br, path in file_refs:
        # Use path relative to SISR group with folder structure via name only — flat with full relative path
        rel = path.relative_to(APP).as_posix()
        a(f'\t\t{fr} /* {rel} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {path.name}; path = {rel}; sourceTree = "<group>"; }};')
    a(f'\t\t{ids["assets"]} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};')
    a(f'\t\t{ids["privacy"]} /* PrivacyInfo.xcprivacy */ = {{isa = PBXFileReference; lastKnownFileType = text.xml; path = PrivacyInfo.xcprivacy; sourceTree = "<group>"; }};')
    a(f'\t\t{ids["info"]} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};')
    a(f'\t\t{ids["entitlements"]} /* SISR.entitlements */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = SISR.entitlements; sourceTree = "<group>"; }};')
    a("/* End PBXFileReference section */")

    a("/* Begin PBXFrameworksBuildPhase section */")
    a(f"\t\t{ids['frameworks']} /* Frameworks */ = {{")
    a("\t\t\tisa = PBXFrameworksBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a(f"\t\t\t\t{ids['package_build']} /* SISRKit in Frameworks */,")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXFrameworksBuildPhase section */")

    a("/* Begin PBXGroup section */")
    a(f"\t\t{ids['main_group']} = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a(f"\t\t\t\t{ids['app_group']} /* SISR */,")
    a(f"\t\t\t\t{ids['products']} /* Products */,")
    a("\t\t\t);")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    a(f"\t\t{ids['products']} /* Products */ = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    a(f"\t\t\t\t{ids['product']} /* SISR.app */,")
    a("\t\t\t);")
    a("\t\t\tname = Products;")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    a(f"\t\t{ids['app_group']} /* SISR */ = {{")
    a("\t\t\tisa = PBXGroup;")
    a("\t\t\tchildren = (")
    for fr, _br, path in file_refs:
        a(f"\t\t\t\t{fr} /* {path.name} */,")
    a(f"\t\t\t\t{ids['assets']} /* Assets.xcassets */,")
    a(f"\t\t\t\t{ids['privacy']} /* PrivacyInfo.xcprivacy */,")
    a(f"\t\t\t\t{ids['info']} /* Info.plist */,")
    a(f"\t\t\t\t{ids['entitlements']} /* SISR.entitlements */,")
    a("\t\t\t);")
    a("\t\t\tpath = SISR;")
    a('\t\t\tsourceTree = "<group>";')
    a("\t\t};")
    a("/* End PBXGroup section */")

    a("/* Begin PBXNativeTarget section */")
    a(f"\t\t{ids['target']} /* SISR */ = {{")
    a("\t\t\tisa = PBXNativeTarget;")
    a(f'\t\t\tbuildConfigurationList = {ids["tgt_configs"]} /* Build configuration list for PBXNativeTarget "SISR" */;')
    a("\t\t\tbuildPhases = (")
    a(f"\t\t\t\t{ids['sources']} /* Sources */,")
    a(f"\t\t\t\t{ids['frameworks']} /* Frameworks */,")
    a(f"\t\t\t\t{ids['resources']} /* Resources */,")
    a("\t\t\t);")
    a("\t\t\tbuildRules = (")
    a("\t\t\t);")
    a("\t\t\tdependencies = (")
    a("\t\t\t);")
    a("\t\t\tname = SISR;")
    a(f"\t\t\tpackageProductDependencies = ({ids['product_dep']} /* SISRKit */,);")
    a("\t\t\tproductName = SISR;")
    a(f"\t\t\tproductReference = {ids['product']} /* SISR.app */;")
    a('\t\t\tproductType = "com.apple.product-type.application";')
    a("\t\t};")
    a("/* End PBXNativeTarget section */")

    a("/* Begin PBXProject section */")
    a(f"\t\t{ids['project']} /* Project object */ = {{")
    a("\t\t\tisa = PBXProject;")
    a("\t\t\tattributes = {LastSwiftUpdateCheck = 1500; LastUpgradeCheck = 1500;};")
    a(f'\t\t\tbuildConfigurationList = {ids["proj_configs"]} /* Build configuration list for PBXProject "SISR" */;')
    a('\t\t\tcompatibilityVersion = "Xcode 14.0";')
    a("\t\t\tdevelopmentRegion = en;")
    a("\t\t\thasScannedForEncodings = 0;")
    a("\t\t\tknownRegions = (en, Base,);")
    a(f"\t\t\tmainGroup = {ids['main_group']};")
    a(f"\t\t\tpackageReferences = ({ids['package']} /* XCLocalSwiftPackageReference */,);")
    a(f"\t\t\tproductRefGroup = {ids['products']} /* Products */;")
    a('\t\t\tprojectDirPath = "";')
    a('\t\t\tprojectRoot = "";')
    a(f"\t\t\ttargets = ({ids['target']} /* SISR */,);")
    a("\t\t};")
    a("/* End PBXProject section */")

    a("/* Begin PBXResourcesBuildPhase section */")
    a(f"\t\t{ids['resources']} /* Resources */ = {{")
    a("\t\t\tisa = PBXResourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    a(f"\t\t\t\t{ids['assets_build']} /* Assets.xcassets in Resources */,")
    a(f"\t\t\t\t{ids['privacy_build']} /* PrivacyInfo.xcprivacy in Resources */,")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXResourcesBuildPhase section */")

    a("/* Begin PBXSourcesBuildPhase section */")
    a(f"\t\t{ids['sources']} /* Sources */ = {{")
    a("\t\t\tisa = PBXSourcesBuildPhase;")
    a("\t\t\tbuildActionMask = 2147483647;")
    a("\t\t\tfiles = (")
    for _fr, br, path in file_refs:
        a(f"\t\t\t\t{br} /* {path.name} in Sources */,")
    a("\t\t\t);")
    a("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    a("\t\t};")
    a("/* End PBXSourcesBuildPhase section */")

    def cfg(cid: str, name: str, target: bool) -> None:
        a(f"\t\t{cid} /* {name} */ = {{")
        a("\t\t\tisa = XCBuildConfiguration;")
        a("\t\t\tbuildSettings = {")
        if not target:
            a("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
            a("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
            a('\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;')
            a('\t\t\t\tSDKROOT = macosx;')
            a('\t\t\t\tSWIFT_VERSION = 5.9;')
            # App Store Connect requires dSYMs matching the uploaded binary UUIDs.
            if name == "Debug":
                a('\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;')
                a("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
                a('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";')
                a("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
            else:
                a('\t\t\t\tCOPY_PHASE_STRIP = NO;')
                a('\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
                a("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
        else:
            a("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
            a("\t\t\t\tCODE_SIGN_ENTITLEMENTS = SISR/SISR.entitlements;")
            a("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
            a("\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;")
            a("\t\t\t\tCURRENT_PROJECT_VERSION = 5;")
            a("\t\t\t\tDEVELOPMENT_TEAM = 2D8MBBQWXH;")
            a("\t\t\t\tENABLE_HARDENED_RUNTIME = YES;")
            a("\t\t\t\tGENERATE_INFOPLIST_FILE = NO;")
            a("\t\t\t\tINFOPLIST_FILE = SISR/Info.plist;")
            a('\t\t\t\tLD_RUNPATH_SEARCH_PATHS = ("$(inherited)", "@executable_path/../Frameworks");')
            a("\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 14.0;")
            a("\t\t\t\tMARKETING_VERSION = 1.0.4;")
            a("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.timelapsetech.sisr;")
            a('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
            a("\t\t\t\tSWIFT_VERSION = 5.9;")
            if name == "Release":
                a('\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
                a("\t\t\t\tSTRIP_INSTALLED_PRODUCT = YES;")
                a('\t\t\t\tSTRIP_STYLE = "non-global";')
        a("\t\t\t};")
        a(f"\t\t\tname = {name};")
        a("\t\t};")

    a("/* Begin XCBuildConfiguration section */")
    cfg(ids["dbg_proj"], "Debug", False)
    cfg(ids["rel_proj"], "Release", False)
    cfg(ids["dbg_tgt"], "Debug", True)
    cfg(ids["rel_tgt"], "Release", True)
    a("/* End XCBuildConfiguration section */")

    a("/* Begin XCConfigurationList section */")
    a(f'\t\t{ids["proj_configs"]} /* Build configuration list for PBXProject "SISR" */ = {{')
    a("\t\t\tisa = XCConfigurationList;")
    a(f"\t\t\tbuildConfigurations = ({ids['dbg_proj']} /* Debug */, {ids['rel_proj']} /* Release */,);")
    a("\t\t\tdefaultConfigurationIsVisible = 0;")
    a("\t\t\tdefaultConfigurationName = Release;")
    a("\t\t};")
    a(f'\t\t{ids["tgt_configs"]} /* Build configuration list for PBXNativeTarget "SISR" */ = {{')
    a("\t\t\tisa = XCConfigurationList;")
    a(f"\t\t\tbuildConfigurations = ({ids['dbg_tgt']} /* Debug */, {ids['rel_tgt']} /* Release */,);")
    a("\t\t\tdefaultConfigurationIsVisible = 0;")
    a("\t\t\tdefaultConfigurationName = Release;")
    a("\t\t};")
    a("/* End XCConfigurationList section */")

    a("/* Begin XCLocalSwiftPackageReference section */")
    a(f"\t\t{ids['package']} /* XCLocalSwiftPackageReference */ = {{")
    a("\t\t\tisa = XCLocalSwiftPackageReference;")
    a("\t\t\trelativePath = Packages/SISRKit;")
    a("\t\t};")
    a("/* End XCLocalSwiftPackageReference section */")

    a("/* Begin XCSwiftPackageProductDependency section */")
    a(f"\t\t{ids['product_dep']} /* SISRKit */ = {{")
    a("\t\t\tisa = XCSwiftPackageProductDependency;")
    a(f"\t\t\tpackage = {ids['package']} /* XCLocalSwiftPackageReference */;")
    a("\t\t\tproductName = SISRKit;")
    a("\t\t};")
    a("/* End XCSwiftPackageProductDependency section */")

    a("\t};")
    a(f"\trootObject = {ids['project']} /* Project object */;")
    a("}")

    PROJECT.mkdir(exist_ok=True)
    (PROJECT / "project.pbxproj").write_text("\n".join(o) + "\n")

    scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / "SISR.xcscheme").write_text(
        f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['target']}" BuildableName="SISR.app" BlueprintName="SISR" ReferencedContainer="container:SISR.xcodeproj"/>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['target']}" BuildableName="SISR.app" BlueprintName="SISR" ReferencedContainer="container:SISR.xcodeproj"/>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{ids['target']}" BuildableName="SISR.app" BlueprintName="SISR" ReferencedContainer="container:SISR.xcodeproj"/>
    </BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>
"""
    )
    print(f"Generated {PROJECT} with {len(swift_files)} sources")


if __name__ == "__main__":
    main()
