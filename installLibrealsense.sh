#!/bin/bash
# Builds the Intel Realsense library librealsense on a Jetson Nano Development Kit
# Copyright (c) 2016-19 Jetsonhacks 
# MIT License

# Jetson Nano; L4T 32.1.0

# librealsense requires CMake 3.13+ to build with CUDA 10; the repositories hold earlier version
# In this script, we build 3.14 but do not install it

LIBREALSENSE_DIRECTORY=${HOME}/librealsense
LIBREALSENSE_VERSION=v2.21.0
INSTALL_DIR=$PWD
NVCC_PATH=/usr/local/cuda-10.0/bin/nvcc

# You don't need to build CMake unless you are using CUDA
USE_CUDA=false
BUILD_CMAKE=true

function usage
{
    echo "usage: ./installLibrealsense.sh [[-c ] | [-h]]"
    echo "-n | --no_cmake   Do not build CMake 3.11"
    echo "-c | --build_with_cuda  Build with CUDA"
    echo "-h | --help  This message"
}

# Iterate through command line inputs
while [ "$1" != "" ]; do
    case $1 in
        -n | --no_cmake )       BUILD_CMAKE=false
                                ;;
        -c | --build_with_cuda )  USE_CUDA=true
                                ;;
        -h | --help )           usage
                                exit
                                ;;
        * )                     usage
                                exit 1
    esac
    shift
done

if [ "$USE_CUDA" = false ] ; then
   BUILD_CMAKE=false
fi

echo "Build with CUDA: "$USE_CUDA
echo "Build CMake: "$BUILD_CMAKE

red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`
# e.g. echo "${red}The red tail hawk ${green}loves the green grass${reset}"


echo ""
echo "Please make sure that no RealSense cameras are currently attached"
echo ""
read -n 1 -s -r -p "Press any key to continue"
echo ""

if [ ! -d "$LIBREALSENSE_DIRECTORY" ] ; then
  # clone librealsense
  cd ${HOME}
  echo "${green}Cloning librealsense${reset}"
  git clone https://github.com/IntelRealSense/librealsense.git
fi

# Is the version of librealsense current enough?
cd $LIBREALSENSE_DIRECTORY
VERSION_TAG=$(git tag -l $LIBREALSENSE_VERSION)
if [ ! $VERSION_TAG  ] ; then
   echo ""
  tput setaf 1
  echo "==== librealsense Version Mismatch! ============="
  tput sgr0
  echo ""
  echo "The installed version of librealsense is not current enough for these scripts."
  echo "This script needs librealsense tag version: "$LIBREALSENSE_VERSION "but it is not available."
  echo "This script patches librealsense, the patches apply on the expected version."
  echo "Please upgrade librealsense before attempting to install again."
  echo ""
  exit 1
fi

# Checkout version the last tested version of librealsense
git checkout $LIBREALSENSE_VERSION

# Install the dependencies
cd $INSTALL_DIR
sudo ./scripts/installDependencies.sh

# Do we need to install CMake?
if [ "$BUILD_CMAKE" = true ] ; then
  echo "Building CMake"
  ./scripts/buildCMake.sh
  CMAKE_BUILD_OK=$?
  if [ $CMAKE_BUILD_OK -ne 0 ] ; then
    echo "CMake build failure. Exiting"
    exit 1
  fi
fi

cd $LIBREALSENSE_DIRECTORY
git checkout $LIBREALSENSE_VERSION

echo "${green}Applying Model-Views Patch${reset}"
# The render loop of the post processing does not yield; add a sleep
patch -p1 -i $INSTALL_DIR/patches/model-views.patch

# echo "${green}Applying Incomplete Frames Patch${reset}"
# The Jetson tends to return incomplete frames at high frame rates; suppress error logging
# patch -p1 -i $INSTALL_DIR/patches/incomplete-frame.patch


echo "${green}Applying udev rules${reset}"
# Copy over the udev rules so that camera can be run from user space
sudo cp config/99-realsense-libusb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules && udevadm trigger

# Now compile librealsense and install
mkdir build 
cd build
# Build examples, including graphical ones
echo "${green}Configuring Make system${reset}"
# Use the CMake version that we built, must be > 3.8
# Build with CUDA (default), the CUDA flag is USE_CUDA, ie -DUSE_CUDA=true
export CUDACXX=$NVCC_PATH
export PATH=${PATH}:/usr/local/cuda/bin
export LD_LIBRARY_PATH=${LD_LIBRARY_PATH}:/usr/local/cuda/lib64

if [ "$USE_CUDA" = true ] ; then
   ${HOME}/CMake/bin/cmake ../ -DBUILD_EXAMPLES=true -DBUILD_WITH_CUDA="$USE_CUDA" -DCMAKE_BUILD_TYPE=release -DBUILD_PYTHON_BINDINGS=true
else
   /usr/bin/cmake ../ -DBUILD_EXAMPLES=true -DBUILD_WITH_CUDA="$USE_CUDA" -DCMAKE_BUILD_TYPE=release -DBUILD_PYTHON_BINDINGS=true
fi

export PYTHONPATH=$PYTHONPATH:/usr/local/lib

# The library will be installed in /usr/local/lib, header files in /usr/local/include
# The demos, tutorials and tests will located in /usr/local/bin.
echo "${green}Building librealsense, headers, tools and demos${reset}"

NUM_CPU=$(nproc)
time make -j$(($NUM_CPU - 1))
if [ $? -eq 0 ] ; then
  echo "librealsense make successful"
else
  # Try to make again; Sometimes there are issues with the build
  # because of lack of resources or concurrency issues
  echo "librealsense did not build " >&2
  echo "Retrying ... "
  # Single thread this time
  time make 
  if [ $? -eq 0 ] ; then
    echo "librealsense make successful"
  else
    # Try to make again
    echo "librealsense did not successfully build" >&2
    echo "Please fix issues and retry build"
    exit 1
  fi
fi
echo "${green}Installing librealsense, headers, tools and demos${reset}"
sudo make install
echo "${green}Library Installed${reset}"
echo " "
echo " -----------------------------------------"
echo "The library is installed in /usr/local/lib"
echo "The header files are in /usr/local/include"
echo "The demos and tools are located in /usr/local/bin"
echo " "
echo " -----------------------------------------"
echo " "



