#!/bin/bash

# This script will build chromium with accelerated decoding support for 
# jetson platforms. The resulting debian will be in the $OUTPUT_DIR directory. 
# If this folder doesn't exist, it will be created.
#
# This script can be run on your host machine, however, it is recommended to do it 
# in a container. 
# To create the container run the following command:
#
# sudo docker run --name chromium -it --privileged -v /home/$USER/chromium_output:/root/chromium_output ubuntu:18.04

WORK_DIR=${HOME}/chromium

TOOLS_REPO=https://chromium.googlesource.com/chromium/tools/depot_tools.git
TOOLS_DIR=${WORK_DIR}/tools

CHROMIUM_TAG=90.0.4400.4
CHROMIUM_DIR=${WORK_DIR}/chromium
CHROMIUM_SRC_DIR=${CHROMIUM_DIR}/src
CHROMIUM_BUILD_DIR=${CHROMIUM_SRC_DIR}/build

PATCHES_REPO=https://github.com/RidgeRun/chromium-jetson-accelerated.git
PATCHES_BRANCH=v90.0.4400.4
PATCHES_DIR=${CHROMIUM_DIR}/patches

OUTPUT_DIR=${HOME}/chromium_output

msg() {
    echo
    echo "$1"
    echo
}

create_dir() {
    if [[ ! -d $1 ]]
    then
        mkdir -p $1
    fi
}

prepare() {
    msg "Preparing..."
    
    create_dir ${WORK_DIR}
    create_dir ${CHROMIUM_DIR}
    create_dir ${OUTPUT_DIR}
    apt-get update
    apt-get install -y git curl wget lsb-release vim python2.7 sudo
    update-alternatives --install /usr/bin/python python /usr/bin/python2.7 1
}

get_tools() {
    msg "Getting tools..."
    
    git clone ${TOOLS_REPO} ${TOOLS_DIR}
    export PATH=$PATH:${TOOLS_DIR}
}

get_chromium() {
    msg "Getting chromium..."

    cd ${CHROMIUM_DIR}
    fetch chromium
    cd ${CHROMIUM_SRC_DIR}
    git checkout tags/${CHROMIUM_TAG} -b ${CHROMIUM_TAG}
    gclient sync --with_branch_heads --with_tags
}

patch_chromium() {
    msg "Patching chromium..."
    
    git clone --branch ${PATCHES_BRANCH} ${PATCHES_REPO} ${PATCHES_DIR}
    cd ${CHROMIUM_SRC_DIR}
    for p in `ls ${PATCHES_DIR}/patches/*.patch`
    do
        patch -p1 -i ${p}
    done
}

build_chromium() {
    msg "Building chromium, this will take a while..."
    
    # Get some dependencies ready
    ${CHROMIUM_BUILD_DIR}/install-build-deps.sh
    ${CHROMIUM_BUILD_DIR}/install-build-deps.sh --arm
    ${CHROMIUM_BUILD_DIR}/linux/sysroot_scripts/install-sysroot.py --arch=arm64
    
    # Actual build (prepare)
    GYP_DEFINES="target_arch=arm64" gclient runhooks
    export GYP_CROSSCOMPILE=1
    gn gen out/release-90/ "--args=is_debug=false target_cpu=\"arm64\" is_component_build=false use_ozone=true use_v4l2_codec=true use_linux_v4l2_only=true use_v4lplugin=true proprietary_codecs=true ffmpeg_branding=\"Chrome\" use_nvidia_v4l2=true enable_linux_installer = true"
    
    # Build
    autoninja -C out/release-90/ chrome chrome_sandbox "chrome/installer/linux:unstable_deb"
    
    cp ${CHROMIUM_SRC_DIR}/out/release-90/chromium-browser-unstable_90.0.4400.4-1_arm64.deb $OUTPUT_DIR
    msg "Build done!"
}

# Do stuff
prepare
get_tools
get_chromium
patch_chromium
build_chromium
