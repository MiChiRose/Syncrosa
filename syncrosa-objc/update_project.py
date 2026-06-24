import os
import uuid

def generate_id():
    return uuid.uuid4().hex[:24].upper()

project_path = 'syncrosa-objc/Syncrosa.xcodeproj/project.pbxproj'
sources_root = 'syncrosa-objc/Sources'
tests_root = 'syncrosa-objc/SyncrosaTests'

# 1. Map Filesystem (Sources)
file_to_ref_id = {}
all_m_files = []
all_res_files = []
groups = {} # rel_path -> id

for root, dirs, files in os.walk(sources_root):
    rel_root = os.path.relpath(root, sources_root)
    if rel_root == '.': rel_root = ''
    
    current_files = []
    for file in files:
        if file.endswith(('.h', '.m', '.xib', '.strings', '.plist', '.pem', '.jpeg', '.icns')):
            f_id = generate_id()
            file_to_ref_id[os.path.join('Sources', rel_root, file)] = f_id
            if file.endswith('.m'): all_m_files.append((file, f_id))
            if file.endswith(('.xib', '.strings', '.pem', '.jpeg', '.icns')): all_res_files.append((file, f_id))
    
    groups[rel_root] = generate_id()

# 2. Map Filesystem (Tests)
tests_files = []
tests_group_id = generate_id()
for file in os.listdir(tests_root):
    if file.endswith(('.h', '.m', '.plist')):
        f_id = generate_id()
        file_to_ref_id[os.path.join('Tests', file)] = f_id
        tests_files.append((file, f_id))

# 3. Build Sections
pbx_build_file = ""
pbx_file_ref = ""
id_to_build_id = {}

for full_path, f_id in file_to_ref_id.items():
    filename = os.path.basename(full_path)
    if filename.endswith('.h'): ftype = 'sourcecode.c.h'
    elif filename.endswith('.m'): ftype = 'sourcecode.c.objc'
    elif filename.endswith('.xib'): ftype = 'file.xib'
    elif filename.endswith('.strings'): ftype = 'text.plist.strings'
    elif filename.endswith('.pem'): ftype = 'text'
    elif filename.endswith('.jpeg'): ftype = 'image.jpeg'
    elif filename.endswith('.icns'): ftype = 'image.icns'
    else: ftype = 'text.plist.xml'
    
    pbx_file_ref += f'\t\t{f_id} /* {filename} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; path = "{filename}"; sourceTree = "<group>"; }};\n'
    
    if not filename.endswith('.h') and not filename.endswith('.plist'):
        b_id = generate_id()
        id_to_build_id[f_id] = b_id
        pbx_build_file += f'\t\t{b_id} /* {filename} in Build */ = {{isa = PBXBuildFile; fileRef = {f_id} /* {filename} */; }};\n'

# 4. Groups Section
new_groups = ""

# Subgroups for Sources
for rel_path, g_id in sorted(groups.items(), key=lambda x: len(x[0]), reverse=True):
    children = ""
    # Files
    for full_path, f_id in file_to_ref_id.items():
        if full_path.startswith('Sources'):
            rel_f_path = os.path.relpath(full_path, 'Sources')
            if os.path.dirname(rel_f_path) == rel_path or (rel_path == '' and os.path.dirname(rel_f_path) == '.'):
                children += f'\t\t\t\t{f_id} /* {os.path.basename(full_path)} */,\n'
    # Subdirs
    for sub_path, sub_id in groups.items():
        if os.path.dirname(sub_path) == rel_path and sub_path != rel_path:
            children += f'\t\t\t\t{sub_id} /* {os.path.basename(sub_path)} */,\n'
            
    name = os.path.basename(rel_path) if rel_path else "Sources"
    path_val = name if rel_path else "Sources"
    new_groups += f'\t\t{g_id} /* {name} */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{children}\t\t\t);\n\t\t\tpath = "{path_val}";\n\t\t\tsourceTree = "<group>";\n\t\t}};\n'

# Tests Group
test_children = ""
for fname, f_id in tests_files:
    test_children += f'\t\t\t\t{f_id} /* {fname} */,\n'
new_groups += f'\t\t{tests_group_id} /* Tests */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{test_children}\t\t\t);\n\t\t\tpath = "SyncrosaTests";\n\t\t\tsourceTree = "<group>";\n\t\t}};\n'

# Products Group
product_app_id = "5281AC572FDAE21700B6EAAC"
product_test_id = "5281AC6A2FDAE21700B6EAAC"
new_groups += f'\t\t5281AC582FDAE21700B6EAAC /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{product_app_id} /* Syncrosa.app */,\n\t\t\t\t{product_test_id} /* SyncrosaTests.xctest */,\n\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = "<group>";\n\t\t}};\n'

# Main Group
main_group_id = "5281AC4E2FDAE21700B6EAAC"
new_groups += f'\t\t{main_group_id} /* Project Group */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n\t\t\t\t{groups[""]} /* Sources */,\n\t\t\t\t{tests_group_id} /* Tests */,\n\t\t\t\t5281AC582FDAE21700B6EAAC /* Products */,\n\t\t\t);\n\t\t\tsourceTree = "<group>";\n\t\t}};\n'

# 5. Targets
app_target_id = "5281AC562FDAE21700B6EAAC"
test_target_id = "5281AC692FDAE21700B6EAAC"

# 6. Build Phases
src_phase_id = "5281AC532FDAE21700B6EAAC"
res_phase_id = "5281AC552FDAE21700B6EAAC"
test_src_phase_id = generate_id()

app_src_files = ""
app_res_files = ""
for full_path, f_id in file_to_ref_id.items():
    if full_path.startswith('Sources'):
        filename = os.path.basename(full_path)
        if f_id in id_to_build_id:
            b_id = id_to_build_id[f_id]
            if filename.endswith('.m'):
                app_src_files += f'\t\t\t\t{b_id} /* {filename} in Sources */,\n'
            else:
                app_res_files += f'\t\t\t\t{b_id} /* {filename} in Resources */,\n'

test_src_files = ""
for fname, f_id in tests_files:
    if f_id in id_to_build_id:
        test_src_files += f'\t\t\t\t{id_to_build_id[f_id]} /* {fname} in Build */,\n'

# 7. Final Content
content = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 46;
	objects = {{

/* Begin PBXBuildFile section */
{pbx_build_file}/* End PBXBuildFile section */

/* Begin PBXContainerItemProxy section */
\t\t5281AC6B2FDAE21700B6EAAC /* PBXContainerItemProxy */ = {{
\t\t\tisa = PBXContainerItemProxy;
\t\t\tcontainerPortal = 5281AC4F2FDAE21700B6EAAC /* Project object */;
\t\t\tproxyType = 1;
\t\t\tremoteGlobalIDString = 5281AC562FDAE21700B6EAAC;
\t\t\tremoteInfo = "Syncrosa";
\t\t}};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
{pbx_file_ref}\t\t{product_app_id} /* Syncrosa.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = "Syncrosa.app"; sourceTree = BUILT_PRODUCTS_DIR; }};
\t\t{product_test_id} /* SyncrosaTests.xctest */ = {{isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = "SyncrosaTests.xctest"; sourceTree = BUILT_PRODUCTS_DIR; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
\t\t5281AC542FDAE21700B6EAAC /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t5281AC672FDAE21700B6EAAC /* Frameworks */ = {{
\t\t\tisa = PBXFrameworksBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
{new_groups}/* End PBXGroup section */

/* Begin PBXNativeTarget section */
\t\t5281AC562FDAE21700B6EAAC /* Syncrosa */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 5281AC742FDAE21700B6EAAC /* Build configuration list for PBXNativeTarget "Syncrosa" */;
\t\t\tbuildPhases = (
\t\t\t\t{src_phase_id} /* Sources */,
\t\t\t\t5281AC542FDAE21700B6EAAC /* Frameworks */,
\t\t\t\t{res_phase_id} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tname = "Syncrosa";
\t\t\tproductName = "Syncrosa";
\t\t\tproductReference = {product_app_id} /* Syncrosa.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
\t\t5281AC692FDAE21700B6EAAC /* SyncrosaTests */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = 5281AC772FDAE21700B6EAAC /* Build configuration list for PBXNativeTarget "SyncrosaTests" */;
\t\t\tbuildPhases = (
\t\t\t\t{test_src_phase_id} /* Sources */,
\t\t\t\t5281AC672FDAE21700B6EAAC /* Frameworks */,
\t\t\t\t5281AC682FDAE21700B6EAAC /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t\t5281AC6C2FDAE21700B6EAAC /* PBXTargetDependency */,
\t\t\t);
\t\t\tname = "SyncrosaTests";
\t\t\tproductName = "SyncrosaTests";
\t\t\tproductReference = {product_test_id} /* SyncrosaTests.xctest */;
\t\t\tproductType = "com.apple.product-type.bundle.unit-test";
\t\t}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
\t\t5281AC4F2FDAE21700B6EAAC /* Project object */ = {{
\t\t\tisa = PBXProject;
\t\t\tattributes = {{
\t\t\t\tLastUpgradeCheck = 0610;
\t\t\t\tORGANIZATIONNAME = "MacBook Pro";
\t\t\t\tTargetAttributes = {{
\t\t\t\t\t5281AC562FDAE21700B6EAAC = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 6.1;
\t\t\t\t\t}};
\t\t\t\t\t5281AC692FDAE21700B6EAAC = {{
\t\t\t\t\t\tCreatedOnToolsVersion = 6.1;
\t\t\t\t\t\tTestTargetID = 5281AC562FDAE21700B6EAAC;
\t\t\t\t\t}};
\t\t\t\t}};
\t\t\t}};
\t\t\tbuildConfigurationList = 5281AC522FDAE21700B6EAAC /* Build configuration list for PBXProject "Syncrosa" */;
\t\t\tcompatibilityVersion = "Xcode 3.2";
\t\t\tdevelopmentRegion = English;
\t\t\thasScannedForEncodings = 0;
\t\t\tknownRegions = (
\t\t\t\ten,
\t\t\t\tBase,
\t\t\t);
\t\t\tmainGroup = {main_group_id};
\t\t\tproductRefGroup = 5281AC582FDAE21700B6EAAC /* Products */;
\t\t\tprojectDirPath = "";
\t\t\tprojectRoot = "";
\t\t\ttargets = (
\t\t\t\t5281AC562FDAE21700B6EAAC /* Syncrosa */,
\t\t\t\t5281AC692FDAE21700B6EAAC /* SyncrosaTests */,
\t\t\t);
\t\t}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
\t\t5281AC552FDAE21700B6EAAC /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_res_files}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t5281AC682FDAE21700B6EAAC /* Resources */ = {{
\t\t\tisa = PBXResourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
\t\t5281AC532FDAE21700B6EAAC /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{app_src_files}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
\t\t{test_src_phase_id} /* Sources */ = {{
\t\t\tisa = PBXSourcesBuildPhase;
\t\t\tbuildActionMask = 2147483647;
\t\t\tfiles = (
{test_src_files}\t\t\t);
\t\t\trunOnlyForDeploymentPostprocessing = 0;
\t\t}};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
\t\t5281AC6C2FDAE21700B6EAAC /* PBXTargetDependency */ = {{
\t\t\tisa = PBXTargetDependency;
\t\t\ttarget = 5281AC562FDAE21700B6EAAC /* Syncrosa */;
\t\t\ttargetProxy = 5281AC6B2FDAE21700B6EAAC /* PBXContainerItemProxy */;
\t\t}};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
\t\t5281AC502FDAE21700B6EAAC /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++0x";
\t\t\t\tCLANG_CXX_LIBRARY = "libc++";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu99;
\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;
\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tGCC_SYMBOLS_PRIVATE_EXTERN = NO;
\t\t\t\tGCC_WARN_64_BIT_CONVERT_TO_32_BIT_AS_SAFE = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 10.13;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = YES;
\t\t\t\tONLY_ACTIVE_ARCH = YES;
\t\t\t\tSDKROOT = macosx;
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t5281AC512FDAE21700B6EAAC /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = "gnu++0x";
\t\t\t\tCLANG_CXX_LIBRARY = "libc++";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu99;
\t\t\t\tGCC_WARN_64_BIT_CONVERT_TO_32_BIT_AS_SAFE = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = 10.13;
\t\t\t\tMTL_ENABLE_DEBUG_INFO = NO;
\t\t\t\tSDKROOT = macosx;
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t5281AC752FDAE21700B6EAAC /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tINFOPLIST_FILE = Sources/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t5281AC762FDAE21700B6EAAC /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tCOMBINE_HIDPI_IMAGES = YES;
\t\t\t\tINFOPLIST_FILE = Sources/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
\t\t5281AC782FDAE21700B6EAAC /* Debug */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tFRAMEWORK_SEARCH_PATHS = (
\t\t\t\t\t"$(DEVELOPER_FRAMEWORKS_DIR)",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tGCC_PREPROCESSOR_DEFINITIONS = (
\t\t\t\t\t"DEBUG=1",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tINFOPLIST_FILE = "SyncrosaTests/Info.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Syncrosa.app/Contents/MacOS/Syncrosa";
\t\t\t}};
\t\t\tname = Debug;
\t\t}};
\t\t5281AC792FDAE21700B6EAAC /* Release */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";
\t\t\t\tFRAMEWORK_SEARCH_PATHS = (
\t\t\t\t\t"$(DEVELOPER_FRAMEWORKS_DIR)",
\t\t\t\t\t"$(inherited)",
\t\t\t\t);
\t\t\t\tINFOPLIST_FILE = "SyncrosaTests/Info.plist";
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks";
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tTEST_HOST = "$(BUILT_PRODUCTS_DIR)/Syncrosa.app/Contents/MacOS/Syncrosa";
\t\t\t}};
\t\t\tname = Release;
\t\t}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
\t\t5281AC522FDAE21700B6EAAC /* Build configuration list for PBXProject "Syncrosa" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t5281AC502FDAE21700B6EAAC /* Debug */,
\t\t\t\t5281AC512FDAE21700B6EAAC /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t5281AC742FDAE21700B6EAAC /* Build configuration list for PBXNativeTarget "Syncrosa" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t5281AC752FDAE21700B6EAAC /* Debug */,
\t\t\t\t5281AC762FDAE21700B6EAAC /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
\t\t5281AC772FDAE21700B6EAAC /* Build configuration list for PBXNativeTarget "SyncrosaTests" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t5281AC782FDAE21700B6EAAC /* Debug */,
\t\t\t\t5281AC792FDAE21700B6EAAC /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
/* End XCConfigurationList section */
\t}};
\trootObject = 5281AC4F2FDAE21700B6EAAC /* Project object */;
}}
"""

with open(project_path, 'w') as f:
    f.write(content)

print("Project file fully reconstructed with Tests and Products.")
