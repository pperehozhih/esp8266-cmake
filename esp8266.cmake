# .o extension is important, so this 2 lines appends new system esp8266 this it's own configuration file esp8266.cmake
set(CMAKE_SYSTEM_NAME ESP8266)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}/Modules")

# esp8266 compiler triplet name
set(TARGET_TRIPLET xtensa-lx106-elf)
# flash size
set(FLASH_SIZE 4m)
# system magic, detect arduino dir and system extension
if(CMAKE_HOST_SYSTEM_NAME MATCHES "Darwin")
    set(USER_HOME $ENV{HOME})
    set(SYSTEM_EXTENSION "")
    set(ARDUINO_DIR "${USER_HOME}/Library/Arduino15")
    set(SYSTEM_LIBRARIES_ROOT /Applications/Arduino.app/Contents/Java/libraries)
    set(USER_LIBRARIES_ROOT "${USER_HOME}/Documents/Arduino/libraries")

elseif(CMAKE_HOST_SYSTEM_NAME MATCHES "Windows")
    if(NOT DEFINED RAW_USER_HOME)
        set(RAW_USER_HOME $ENV{USERPROFILE})
    endif()
    string(REPLACE "\\" "/" USER_HOME ${RAW_USER_HOME})
    set(SYSTEM_EXTENSION ".exe")
    set(RAW_ARDUINO_DIR "${USER_HOME}/Documents/ArduinoData")
    string(REPLACE "\\" "/" ARDUINO_DIR ${RAW_ARDUINO_DIR})
    set(RAW_SYSTEM_LIBRARIES_ROOT "$ENV{PROGRAMFILES}/Arduino/libraries")
    string(REPLACE "\\" "/" SYSTEM_LIBRARIES_ROOT ${RAW_SYSTEM_LIBRARIES_ROOT})
    set(USER_LIBRARIES_ROOT "${USER_HOME}/Documents/Arduino/libraries")
    file(WRITE "${CMAKE_CURRENT_BINARY_DIR}/build.cmd" "${CMAKE_CURRENT_LIST_DIR}/esptool.exe -cd nodemcu -cb 921600 -cp COM4 -ca 0x00000 -cf ${CMAKE_CURRENT_BINARY_DIR}/firmware.bin")
else()
    message(FATAL_ERROR Unsupported build platform.)
endif()

# only esp8266 package inside arduino is interesing
set(ARDUINO_ESP8266_HOME ${ARDUINO_DIR}/packages/esp8266)

# find toolchain bin directory
file(GLOB TOOLCHAIN_SUBDIRS LIST_DIRECTORIES=TRUE "${ARDUINO_ESP8266_HOME}/tools/xtensa-lx106-elf-gcc/*")
list(GET TOOLCHAIN_SUBDIRS 0 TOOLCHAIN_ROOT)
set(TOOLCHAIN_BIN ${TOOLCHAIN_ROOT}/bin)

# find hardware root directory
file(GLOB HARDWARE_SUBDIRS LIST_DIRECTORIES=TRUE "${ARDUINO_ESP8266_HOME}/hardware/esp8266/*")
list(GET HARDWARE_SUBDIRS 0 HARDWARE_ROOT)
set(ESP8266_LIBRARIES_ROOT ${HARDWARE_ROOT}/libraries)

# esptool location
file(GLOB ESPTOOL_SUBDIRS LIST_DIRECTORIES=TRUE "${ARDUINO_ESP8266_HOME}/tools/esptool/*")
list(GET ESPTOOL_SUBDIRS 0 ESPTOOL_DIR)
set(ESPTOOL_APP ${ESPTOOL_DIR}/esptool${SYSTEM_EXTENSION})



link_directories(
    ${HARDWARE_ROOT}/tools/sdk/lib
    ${HARDWARE_ROOT}/tools/sdk/ld
    ${HARDWARE_ROOT}/tools/sdk/libc/xtensa-lx106-elf/lib
)

#setup flags
set(COMMON_FLAGS "-w -g -Os -mlongcalls -ffunction-sections -fdata-sections -MMD -mtext-section-literals -falign-functions=4")
set(CMAKE_CXX_FLAGS "-fno-exceptions -fno-rtti -std=c++11 ${COMMON_FLAGS}")
set(CMAKE_C_FLAGS "-Wpointer-arith -Wno-implicit-function-declaration -Wl,-EL -fno-inline-functions -nostdlib ${COMMON_FLAGS} -std=gnu99")
set(CMAKE_ASM_FLAGS "-x assembler-with-cpp ${COMMON_FLAGS}")
set(CMAKE_EXE_LINKER_FLAGS
        "-nostdlib -Wl,--no-check-sections -u call_user_start -u _printf_float -u _scanf_float -Wl,-static -Teagle.flash.${FLASH_SIZE}.ld -Wl,--gc-sections -Wl,-wrap,system_restart_local -Wl,-wrap,register_chipv6_phy")
# set compilers
set(CMAKE_C_COMPILER "${TOOLCHAIN_BIN}/${TARGET_TRIPLET}-gcc${SYSTEM_EXTENSION}")
set(CMAKE_CXX_COMPILER "${TOOLCHAIN_BIN}/${TARGET_TRIPLET}-g++${SYSTEM_EXTENSION}")
set(CMAKE_ASM_COMPILER "${TOOLCHAIN_BIN}/${TARGET_TRIPLET}-gcc${SYSTEM_EXTENSION}")

# supress compiler checking
set(CMAKE_C_COMPILER_WORKS 1)
set(CMAKE_CXX_COMPILER_WORKS 1)
set(CMAKE_ASM_COMPILER_WORKS 1)

# supress determining compiler id
set(CMAKE_C_COMPILER_ID_RUN 1)
set(CMAKE_CXX_COMPILER_ID_RUN 1)
set(CMAKE_ASM_COMPILER_ID_RUN 1)

# CMAKE_C_COMPILER is not mistake, gcc for all, not g++
set(CMAKE_CXX_LINK_EXECUTABLE
        "<CMAKE_C_COMPILER> <CMAKE_CXX_LINK_FLAGS> <LINK_FLAGS> -o <TARGET> -Wl,--start-group <OBJECTS> <LINK_LIBRARIES> -Wl,--end-group")

set(CMAKE_C_LINK_EXECUTABLE
        "<CMAKE_C_COMPILER> <CMAKE_C_LINK_FLAGS> <LINK_FLAGS> -o <TARGET> -Wl,--start-group <OBJECTS> <LINK_LIBRARIES> -Wl,--end-group")

# macro arduino
# usage:
# arduino(executable_name library1 library2 library3 ...)
# example:
# add_executable(firmware ${USER_SOURCES})
# arduino(firmware ESP8266WiFi Servo)
macro(arduino)
    # first argument - name of executable project, other - library names
    set(ARGUMENTS ${ARGN})
    list(GET ARGUMENTS 0 PROJECT_NAME)
    list(REMOVE_AT ARGUMENTS 0)
    # esp8266 core files
    file(GLOB_RECURSE CORE_ASM_ITEMS "${HARDWARE_ROOT}/cores/esp8266/*.S")
    file(GLOB_RECURSE CORE_C_ITEMS "${HARDWARE_ROOT}/cores/esp8266/*.c")
    file(GLOB_RECURSE CORE_CXX_ITEMS "${HARDWARE_ROOT}/cores/esp8266/*.cpp")

    # create core library
    add_library(arduino_core STATIC ${CORE_ASM_ITEMS} ${CORE_C_ITEMS} ${CORE_CXX_ITEMS})

    # esp8266 include directories
    target_include_directories(arduino_core PUBLIC
            ${HARDWARE_ROOT}/tools/sdk/include
            ${HARDWARE_ROOT}/tools/sdk/lwip2/include
            ${HARDWARE_ROOT}/tools/sdk/libc/xtensa-lx106-elf/include
            ${HARDWARE_ROOT}/cores/esp8266
            ${HARDWARE_ROOT}/variants/d1_mini
            )

    # and esp8266 build definitions
    target_compile_definitions(arduino_core PUBLIC
            -D__ets__
            -DICACHE_FLASH
            -DF_CPU=80000000L
            -DF_CPU=80000000L
            -DARDUINO=10813
            -DARDUINO_ESP8266_ESP01
            -DARDUINO_ARCH_ESP8266
            -DESP8266
            )

    # some other options and link libraries
    target_compile_options(arduino_core PUBLIC -U__STRICT_ANSI__)
    target_link_libraries(arduino_core PUBLIC m gcc hal phy net80211 lwip wpa main pp smartconfig wps crypto axtls)


    # empty lists of library files and include direcories
    set(LIBRARIES_FILES)
    set(LIBRARY_INCLUDE_DIRECTORIES)

    # for each every library determine it's sources and include directories
    foreach(ITEM ${ARGUMENTS})
        # library can be located in 3 different places. 
        # user files located under documents folder
        set(LIBRARY_HOME ${USER_LIBRARIES_ROOT}/${ITEM})
        if(NOT EXISTS ${LIBRARY_HOME})
            # if no user library, look into esp8266 hardware libraries
            set(LIBRARY_HOME ${ESP8266_LIBRARIES_ROOT}/${ITEM})
            if(NOT EXISTS ${LIBRARY_HOME})
                # last chance that it be arduino standard library (as servo or SD)
                set(LIBRARY_HOME ${SYSTEM_LIBRARIES_ROOT}/${ITEM})
                if(NOT EXISTS ${LIBRARY_HOME})
                    message( FATAL_ERROR "Library ${ITEM} does not found")
                endif()
            endif()
        endif()
        # look for library source files
        if (EXISTS "${LIBRARY_HOME}/src")
            set(LIBRARY_HOME "${LIBRARY_HOME}/src")
        endif()
        file(GLOB LIBRARY_S_FILES ${LIBRARY_HOME}/*.S)
        file(GLOB LIBRARY_C_FILES ${LIBRARY_HOME}/*.c)
        file(GLOB LIBRARY_X_FILES ${LIBRARY_HOME}/*.cpp)
        # also look into header files
        file(GLOB_RECURSE LIBRARY_H_FILES ${LIBRARY_HOME}/*.h ${LIBRARY_HOME}/*.hpp)
        # and append it to library sources list
        list(APPEND LIBRARIES_FILES ${LIBRARY_S_FILES} ${LIBRARY_c_FILES} ${LIBRARY_X_FILES} ${LIBRARY_H_FILES})
        list(APPEND LIBRARY_INCLUDE_DIRECTORIES ${LIBRARY_HOME})
    endforeach()
    # exclude header directories duplicates
    list(REMOVE_DUPLICATES LIBRARY_INCLUDE_DIRECTORIES)

    # append all libraries sources to target executable
    target_sources(${PROJECT_NAME} PUBLIC ${LIBRARIES_FILES})
    # add include directories to it
    target_include_directories(${PROJECT_NAME} PUBLIC ${LIBRARY_INCLUDE_DIRECTORIES})

    # append arduino_core library as part of target executable
    target_link_libraries(${PROJECT_NAME} PUBLIC arduino_core)

    # and custom command to create bin file
    add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
            COMMAND ${ESPTOOL_APP} -eo ${HARDWARE_ROOT}/bootloaders/eboot/eboot.elf -bo $<TARGET_FILE_DIR:${PROJECT_NAME}>/${PROJECT_NAME}.bin -bm dio -bf 40 -bz 4M -bs .text -bp 4096 -ec -eo $<TARGET_FILE:firmware> -bs .irom0.text -bs .text -bs .data -bs .rodata -bc -ec
            COMMENT "Building ${PROJECT_NAME}> bin file")
endmacro()
