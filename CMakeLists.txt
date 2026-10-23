cmake_minimum_required(VERSION 3.24)
project(SMSiOS VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
include(CTest)

add_library(sms_disc STATIC native/DiscImage.cpp)
target_include_directories(sms_disc PUBLIC native)
target_compile_options(sms_disc PRIVATE -Wall -Wextra -Werror)

if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
  enable_language(OBJCXX)
  set(SMS_BUNDLE_ID "dev.chasem.sms-iphone-ipad" CACHE STRING "Unique application bundle identifier")
  set(SMS_DEVELOPMENT_TEAM "" CACHE STRING "Apple development team ID; empty builds unsigned")
  if(CMAKE_OSX_SYSROOT MATCHES "[Ss]imulator")
    set(_metal_target "air64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}-simulator")
  else()
    set(_metal_target "air64-apple-ios${CMAKE_OSX_DEPLOYMENT_TARGET}")
  endif()
  set(_metal_air "${CMAKE_CURRENT_BINARY_DIR}/Diagnostic.air")
  set(_metal_library "${CMAKE_CURRENT_BINARY_DIR}/Diagnostic.metallib")
  add_custom_command(OUTPUT "${_metal_library}"
    COMMAND xcrun --sdk "${CMAKE_OSX_SYSROOT}" metal -target "${_metal_target}"
      -c "${CMAKE_CURRENT_SOURCE_DIR}/ios/Diagnostic.metal" -o "${_metal_air}"
    COMMAND xcrun --sdk "${CMAKE_OSX_SYSROOT}" metallib "${_metal_air}" -o "${_metal_library}"
    DEPENDS ios/Diagnostic.metal
    VERBATIM)
  set_source_files_properties("${_metal_library}" PROPERTIES GENERATED TRUE MACOSX_PACKAGE_LOCATION Resources)
  add_executable(sms_ios MACOSX_BUNDLE ios/App.mm ios/MemoryProbe.mm ios/MetalRenderer.mm "${_metal_library}")
  target_compile_options(sms_ios PRIVATE -fobjc-arc -Wall -Wextra)
  target_link_libraries(sms_ios PRIVATE sms_disc
    "-framework UIKit" "-framework Foundation" "-framework Metal"
    "-framework MetalKit" "-framework CoreGraphics" "-framework GameController" "-framework UniformTypeIdentifiers")
  set_target_properties(sms_ios PROPERTIES
    OUTPUT_NAME Sunshine
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_CURRENT_SOURCE_DIR}/ios/Info.plist.in"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${SMS_BUNDLE_ID}"
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${SMS_BUNDLE_ID}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "1,2"
    XCODE_ATTRIBUTE_CODE_SIGN_STYLE Automatic
    XCODE_ATTRIBUTE_ENABLE_BITCODE NO
    XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE NO)
  if(SMS_DEVELOPMENT_TEAM)
    set_target_properties(sms_ios PROPERTIES
      XCODE_ATTRIBUTE_DEVELOPMENT_TEAM "${SMS_DEVELOPMENT_TEAM}"
      XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED YES)
  else()
    set_target_properties(sms_ios PROPERTIES XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO)
  endif()
elseif(BUILD_TESTING)
  add_executable(disc_image_test tests/disc_image_test.cpp)
  target_link_libraries(disc_image_test PRIVATE sms_disc)
  add_test(NAME disc_image COMMAND disc_image_test)
endif()
