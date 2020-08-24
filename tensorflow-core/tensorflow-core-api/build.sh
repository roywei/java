#!/bin/bash
# Script to build native TensorFlow libraries
set -eu

# Allows us to use ccache with Bazel on Mac
export BAZEL_USE_CPP_ONLY_TOOLCHAIN=1

export BAZEL_VC="${VCINSTALLDIR:-}"
if [[ -d $BAZEL_VC ]]; then
    # Work around compiler issues on Windows documented mainly in configure.py but also elsewhere
    export BUILD_FLAGS="--copt=//arch:AVX `#--copt=//arch:AVX2` --copt=-DWIN32_LEAN_AND_MEAN --host_copt=-DWIN32_LEAN_AND_MEAN --copt=-DNOGDI --host_copt=-DNOGDI --copt=-D_USE_MATH_DEFINES --host_copt=-D_USE_MATH_DEFINES --define=override_eigen_strong_inline=true"
    # https://software.intel.com/en-us/articles/intel-optimization-for-tensorflow-installation-guide#wind_B_S
    export PATH=$PATH:$(pwd)/bazel-tensorflow-core-api/external/mkl_windows/lib/
    export PYTHON_BIN_PATH=$(which python.exe)
else
    export BUILD_FLAGS="--copt=-msse4.1 --copt=-msse4.2 --copt=-mavx `#--copt=-mavx2 --copt=-mfma` --cxxopt=-std=c++14 --host_cxxopt=-std=c++14 --linkopt=-lstdc++ --host_linkopt=-lstdc++"
    export PYTHON_BIN_PATH=$(which python3)
fi

if [[ "${EXTENSION:-}" == *mkl* ]]; then
    # Don't use MKL-DNN v1 as it is only currently supported by Linux platform
    export BUILD_FLAGS="$BUILD_FLAGS --config=mkl --define build_with_mkl_dnn_v1_only=false"
fi

if [[ "${EXTENSION:-}" == *gpu* ]]; then
    export BUILD_FLAGS="$BUILD_FLAGS --config=cuda"
    export TF_CUDA_COMPUTE_CAPABILITIES=3.5,sm_52,sm_60,sm_61,7.0,7.5
    if [[ -z ${TF_CUDA_PATHS:-} ]] && [[ -d ${CUDA_PATH:-} ]]; then
        # Work around some issue with Bazel preventing it from detecting CUDA on Windows
        export TF_CUDA_PATHS="$CUDA_PATH"
    fi
fi

BUILD_FLAGS="$BUILD_FLAGS --experimental_repo_remote_exec --python_path="$PYTHON_BIN_PATH" --output_filter=DONT_MATCH_ANYTHING --verbose_failures"

# Always allow distinct host configuration since we rely on the host JVM for a few things (this was disabled by default on windows)
BUILD_FLAGS="$BUILD_FLAGS --distinct_host_configuration=true"

# Build C API of TensorFlow itself including a target to generate ops for Java
bazel build $BUILD_FLAGS \
    @org_tensorflow//tensorflow:tensorflow \
    @org_tensorflow//tensorflow/tools/lib_package:jnilicenses_generate \
    :java_proto_gen_sources \
    :java_op_generator \
    :java_api_import \
    :custom_ops_test

export BAZEL_SRCS=$(pwd -P)/bazel-tensorflow-core-api
export BAZEL_BIN=$(pwd -P)/bazel-bin
export TENSORFLOW_BIN=$BAZEL_BIN/external/org_tensorflow/tensorflow

# Normalize some paths with symbolic links
TENSORFLOW_SO=($TENSORFLOW_BIN/libtensorflow.so.?.?.?)
if [[ -f $TENSORFLOW_SO ]]; then
    export TENSORFLOW_LIB=$TENSORFLOW_SO
    ln -sf $(basename $TENSORFLOW_SO) $TENSORFLOW_BIN/libtensorflow.so
    ln -sf $(basename $TENSORFLOW_SO) $TENSORFLOW_BIN/libtensorflow.so.2
fi
TENSORFLOW_DYLIB=($TENSORFLOW_BIN/libtensorflow.?.?.?.dylib)
if [[ -f $TENSORFLOW_DYLIB ]]; then
    export TENSORFLOW_LIB=$TENSORFLOW_DYLIB
    ln -sf $(basename $TENSORFLOW_DYLIB) $TENSORFLOW_BIN/libtensorflow.dylib
    ln -sf $(basename $TENSORFLOW_DYLIB) $TENSORFLOW_BIN/libtensorflow.2.dylib
fi
TENSORFLOW_DLLS=($TENSORFLOW_BIN/tensorflow.dll.if.lib $TENSORFLOW_BIN/libtensorflow.dll.ifso)
for TENSORFLOW_DLL in ${TENSORFLOW_DLLS[@]}; do
    if [[ -f $TENSORFLOW_DLL ]]; then
        export TENSORFLOW_LIB=$TENSORFLOW_BIN/tensorflow.dll
        ln -sf $(basename $TENSORFLOW_DLL) $TENSORFLOW_BIN/tensorflow.lib
    fi
done
echo "Listing $TENSORFLOW_BIN:" && ls -l $TENSORFLOW_BIN

GEN_SRCS_DIR=src/gen/java
mkdir -p $GEN_SRCS_DIR

# Generate Java operator wrappers
$BAZEL_BIN/java_op_generator \
    --output_dir=$GEN_SRCS_DIR \
    --api_dirs=$BAZEL_SRCS/external/org_tensorflow/tensorflow/core/api_def/base_api,src/bazel/api_def \
    $TENSORFLOW_LIB

# Copy generated Java protos from source jars
cd $GEN_SRCS_DIR
find $TENSORFLOW_BIN/core -name \*-speed-src.jar -exec jar xf {} \;
rm -rf META-INF
