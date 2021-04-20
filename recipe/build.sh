#!/bin/bash

set -x

BUILD_CONFIG=Release

# Use bash "Remove Largest Suffix Pattern" to get rid of all but major version number
PYTHON_MAJOR_VERSION=${PY_VER%%.*}

VTK_ARGS=()

if [ -f "$PREFIX/lib/libOSMesa32${SHLIB_EXT}" ]; then
    VTK_ARGS+=(
        "-DVTK_DEFAULT_RENDER_WINDOW_OFFSCREEN:BOOL=ON"
        "-DVTK_OPENGL_HAS_OSMESA:BOOL=ON"
        "-DOSMESA_INCLUDE_DIR:PATH=${PREFIX}/include"
        "-DOSMESA_LIBRARY:FILEPATH=${PREFIX}/lib/libOSMesa32${SHLIB_EXT}"
    )

    if [[ "${target_platform}" == linux-* ]]; then
        VTK_ARGS+=(
            "-DVTK_USE_X:BOOL=OFF"
        )
    elif [[ "${target_platform}" == osx-* ]]; then
        VTK_ARGS+=(
            "-DVTK_USE_COCOA:BOOL=OFF"
            "-DCMAKE_OSX_SYSROOT:PATH=${CONDA_BUILD_SYSROOT}"
        )
    fi
else
    TCLTK_VERSION=`echo 'puts $tcl_version;exit 0' | tclsh`

    VTK_ARGS+=(
        "-DVTK_DEFAULT_RENDER_WINDOW_OFFSCREEN:BOOL=OFF"
        "-DVTK_OPENGL_HAS_OSMESA:BOOL=OFF"
        "-DVTK_USE_TK:BOOL=ON"
        "-DTCL_INCLUDE_PATH=${PREFIX}/include"
        "-DTK_INCLUDE_PATH=${PREFIX}/include"
        "-DTCL_LIBRARY:FILEPATH=${PREFIX}/lib/libtcl${TCLTK_VERSION}${SHLIB_EXT}"
        "-DTK_LIBRARY:FILEPATH=${PREFIX}/lib/libtk${TCLTK_VERSION}${SHLIB_EXT}"
    )
    if [[ "${target_platform}" == linux-* ]]; then
        VTK_ARGS+=(
            "-DVTK_USE_X:BOOL=ON"
        )
    elif [[ "${target_platform}" == osx-* ]]; then
        VTK_ARGS+=(
            "-DVTK_USE_COCOA:BOOL=ON"
            "-DCMAKE_OSX_SYSROOT:PATH=${CONDA_BUILD_SYSROOT}"
        )
    fi
fi

if [[ "$CONDA_BUILD_CROSS_COMPILATION" == "1" ]]; then
  (
    mkdir build-native
    cd build-native
    export CC=$CC_FOR_BUILD
    export CXX=$CXX_FOR_BUILD
    unset CFLAGS
    unset CXXFLAGS
    unset CPPFLAGS
    export LDFLAGS=${LDFLAGS//$PREFIX/$BUILD_PREFIX}
    cmake -G Ninja -DCMAKE_INSTALL_PREFIX=$SRC_DIR/vtk-compile-tools \
       -DCMAKE_PREFIX_PATH=$BUILD_PREFIX \
       -DCMAKE_INSTALL_LIBDIR=lib \
       -DVTK_BUILD_COMPILE_TOOLS_ONLY=ON ..
    ninja -j${CPU_COUNT}
    ninja install
    cd ..
  )
  MAJ_MIN=$(echo $PKG_VERSION | rev | cut -d"." -f2- | rev)
  CMAKE_ARGS="${CMAKE_ARGS} -DVTKCompileTools_DIR=$SRC_DIR/vtk-compile-tools/lib/cmake/vtkcompiletools-${MAJ_MIN}/"
  CMAKE_ARGS="${CMAKE_ARGS} -DCMAKE_REQUIRE_LARGE_FILE_SUPPORT=1 -DCMAKE_REQUIRE_LARGE_FILE_SUPPORT__TRYRUN_OUTPUT="
fi

mkdir build
cd build || exit

echo "VTK_ARGS:" "${VTK_ARGS[@]}"

# now we can start configuring
cmake -LAH .. -G "Ninja" ${CMAKE_ARGS} \
    -Wno-dev \
    -DCMAKE_BUILD_TYPE=$BUILD_CONFIG \
    -DCMAKE_PREFIX_PATH:PATH="${PREFIX}" \
    -DCMAKE_FIND_FRAMEWORK=LAST \
    -DCMAKE_INSTALL_PREFIX:PATH="${PREFIX}" \
    -DCMAKE_INSTALL_RPATH:PATH="${PREFIX}/lib" \
    -DCMAKE_INSTALL_LIBDIR:PATH=lib \
    -DVTK_BUILD_DOCUMENTATION:BOOL=OFF \
    -DVTK_BUILD_TESTING:BOOL=OFF \
    -DVTK_BUILD_EXAMPLES:BOOL=OFF \
    -DBUILD_SHARED_LIBS:BOOL=ON \
    -DVTK_LEGACY_SILENT:BOOL=OFF \
    -DVTK_HAS_FEENABLEEXCEPT:BOOL=OFF \
    -DVTK_WRAP_PYTHON:BOOL=ON \
    -DVTK_PYTHON_VERSION:STRING="${PYTHON_MAJOR_VERSION}" \
    -DPython3_FIND_STRATEGY=LOCATION \
    -DPython3_ROOT_DIR=${PREFIX} \
    -DPython3_EXECUTABLE=${PREFIX}/bin/python \
    -DVTK_MODULE_ENABLE_VTK_PythonInterpreter:STRING=NO \
    -DVTK_MODULE_ENABLE_VTK_RenderingFreeType:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_RenderingMatplotlib:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_IOFFMPEG:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_ViewsCore:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_ViewsContext2D:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_PythonContext2D:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_RenderingContext2D:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_RenderingContextOpenGL2:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_RenderingCore:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_RenderingOpenGL2:STRING=YES \
    -DVTK_MODULE_ENABLE_VTK_WebGLExporter:STRING=YES \
    -DVTK_DATA_EXCLUDE_FROM_ALL:BOOL=ON \
    -DVTK_USE_EXTERNAL:BOOL=ON \
    -DVTK_MODULE_USE_EXTERNAL_VTK_libharu:BOOL=OFF \
    -DVTK_MODULE_USE_EXTERNAL_VTK_pegtl:BOOL=OFF \
    "${VTK_ARGS[@]}"

# compile & install!
ninja install -v

# The egg-info file is necessary because some packages,
# like mayavi, have a __requires__ in their __invtkRenderWindow::New()it__.py,
# which means pkg_resources needs to be able to find vtk.
# See https://setuptools.readthedocs.io/en/latest/pkg_resources.html#workingset-objects

cat > $SP_DIR/vtk-$PKG_VERSION.egg-info <<FAKE_EGG
Metadata-Version: 2.1
Name: vtk
Version: $PKG_VERSION
Summary: VTK is an open-source toolkit for 3D computer graphics, image processing, and visualization
Platform: UNKNOWN
FAKE_EGG
