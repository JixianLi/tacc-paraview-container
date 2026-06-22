#!/usr/bin/env bash
# Shared %post body for the EGL and OSMesa ParaView+TTK Apptainer images.
# Sourced/run by paraview-egl.def and paraview-osmesa.def — never run directly
# on the host.
#
# Reads:
#   BACKEND — "egl" or "osmesa". Selects backend-specific apt packages and the
#             VTK_OPENGL_HAS_{EGL,OSMESA} cmake flags. Everything else is
#             identical between backends.
#
# Bump these to update versions for both backends in one place:
#   PARAVIEW_VERSION — ParaView git tag to check out.
#   TTK_COMMIT — TTK dev-branch SHA. Pinned because no TTK tagged release yet
#                supports ParaView 6.x; bump when a stable release lands or
#                when you want newer dev fixes.
#   OSPRAY_VERSION — Intel's OSPRay SDK release tag. Installed from Intel's
#                    prebuilt Linux tarball (Ubuntu 24.04 doesn't package
#                    OSPRay / OpenVKL / OIDN). Tarball bundles matched
#                    versions of Embree, OIDN, OpenVKL, rkcommon, and ISPC.

set -eux

: "${BACKEND:?BACKEND must be set to 'egl' or 'osmesa'}"

case "${BACKEND}" in
    egl)
        BACKEND_PACKAGES=(libegl1-mesa-dev libgl1-mesa-dev libglvnd-dev)
        VTK_BACKEND_FLAGS=(-DVTK_OPENGL_HAS_EGL=ON -DVTK_OPENGL_HAS_OSMESA=OFF)
        ;;
    osmesa)
        BACKEND_PACKAGES=(libosmesa6-dev)
        VTK_BACKEND_FLAGS=(-DVTK_OPENGL_HAS_EGL=OFF -DVTK_OPENGL_HAS_OSMESA=ON)
        ;;
    *)
        echo "ERROR: BACKEND must be 'egl' or 'osmesa' (got: ${BACKEND})" >&2
        exit 1
        ;;
esac

export DEBIAN_FRONTEND=noninteractive
PARAVIEW_VERSION=v6.1.1
PARAVIEW_PREFIX=/opt/paraview
TTK_COMMIT=23d59bf147656d031705c99d3249e001b5bfb9c9
OSPRAY_VERSION=3.2.0
OSPRAY_PREFIX=/opt/ospray
export UV_INSTALL_DIR=/usr/local/bin
export UV_PYTHON_INSTALL_DIR=/opt/uv-python

# apt's privilege-drop sandbox can't operate under --fakeroot (uid 42 isn't
# in the user-namespace map); disable it so apt-get can fetch as root.
echo 'APT::Sandbox::User "root";' > /etc/apt/apt.conf.d/no-sandbox

apt-get update
apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ninja-build \
    git \
    ca-certificates \
    curl \
    pkg-config \
    "${BACKEND_PACKAGES[@]}" \
    libpng-dev \
    libjpeg-dev \
    libtiff-dev \
    libhdf5-dev \
    libnetcdf-dev \
    libxml2-dev \
    libexpat1-dev \
    libfreetype-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libtbb-dev \
    libboost-dev \
    libeigen3-dev \
    libsqlite3-dev \
    zlib1g-dev
rm -rf /var/lib/apt/lists/*

# OSPRay + its render-kit deps (Embree, OIDN, OpenVKL, rkcommon, ISPC) aren't
# in Ubuntu 24.04, so install Intel's prebuilt Linux SDK tarball into
# ${OSPRAY_PREFIX}. ParaView's raytracing module picks it up via
# CMAKE_PREFIX_PATH below.
# RenderKit's release filenames use the same arch tokens that `uname -m`
# emits (x86_64, aarch64), so we can build the URL from the native arch
# directly. This keys off the *build host* — correct for native builds on
# x86_64 and ARM (Vista), wrong only for cross/emulated builds.
curl -LsSf -o /tmp/ospray.tar.gz \
    "https://github.com/RenderKit/OSPRay/releases/download/v${OSPRAY_VERSION}/ospray-${OSPRAY_VERSION}.$(uname -m).linux.tar.gz"
mkdir -p "${OSPRAY_PREFIX}"
tar -xzf /tmp/ospray.tar.gz -C "${OSPRAY_PREFIX}" --strip-components=1
rm /tmp/ospray.tar.gz

curl -LsSf https://astral.sh/uv/install.sh | sh
uv python install 3.13
PYBIN="$(uv python find 3.13)"
ln -sf "${PYBIN}" /usr/local/bin/python3.13
ln -sf "${PYBIN}" /usr/local/bin/python3
ln -sf "${PYBIN}" /usr/local/bin/python
chmod -R a+rX /opt/uv-python

mkdir -p /src && cd /src
git clone --recursive --depth 1 --shallow-submodules \
    --branch ${PARAVIEW_VERSION} \
    https://gitlab.kitware.com/paraview/paraview.git

mkdir -p /src/paraview/build && cd /src/paraview/build
cmake .. \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${PARAVIEW_PREFIX} \
    -DPARAVIEW_BUILD_EDITION=CANONICAL \
    -DPARAVIEW_USE_PYTHON=ON \
    -DPARAVIEW_USE_QT=OFF \
    -DPARAVIEW_USE_MPI=OFF \
    -DPARAVIEW_ENABLE_RAYTRACING=ON \
    -DCMAKE_PREFIX_PATH=${OSPRAY_PREFIX} \
    "${VTK_BACKEND_FLAGS[@]}" \
    -DVTK_USE_X=OFF \
    -DVTK_SMP_IMPLEMENTATION_TYPE=TBB \
    -DPython3_EXECUTABLE=/usr/local/bin/python3.13
ninja
ninja install
# Free ParaView source tree before building TTK (saves ~10 GB in build stage).
rm -rf /src/paraview

cd /src
git clone https://github.com/topology-tool-kit/ttk.git
cd ttk && git checkout ${TTK_COMMIT}
mkdir build && cd build
cmake .. \
    -GNinja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=${PARAVIEW_PREFIX} \
    -DParaView_DIR=${PARAVIEW_PREFIX}/lib/cmake/paraview-6.1 \
    -DTTK_BUILD_PARAVIEW_PLUGINS=ON \
    -DTTK_BUILD_VTK_WRAPPERS=ON \
    -DTTK_BUILD_STANDALONE_APPS=OFF \
    -DTTK_ENABLE_OPENMP=ON \
    -DTTK_ENABLE_GRAPHVIZ=OFF \
    -DPython3_EXECUTABLE=/usr/local/bin/python3.13
ninja
ninja install
cd / && rm -rf /src

# Symlink ParaView binaries into /usr/local/bin so they're on PATH even when
# %environment isn't applied (e.g. apptainer exec --cleanenv).
for bin in ${PARAVIEW_PREFIX}/bin/*; do
    [ -x "${bin}" ] && [ ! -d "${bin}" ] && \
        ln -sf "${bin}" "/usr/local/bin/$(basename "${bin}")"
done

PV_SITE="$(ls -d ${PARAVIEW_PREFIX}/lib/python3.13/site-packages 2>/dev/null \
           || ls -d ${PARAVIEW_PREFIX}/lib/python*/site-packages | head -1)"
UV_SITE="$(/usr/local/bin/python3.13 -c 'import site; print(site.getsitepackages()[0])')"
echo "${PV_SITE}" > "${UV_SITE}/paraview.pth"

/usr/local/bin/python3.13 -c "import paraview; print('paraview module imported from', paraview.__file__)"
${PARAVIEW_PREFIX}/bin/pvbatch --version

# Verify TTK installed a loadable plugin somewhere under the ParaView prefix.
# ParaView 6.x's exact plugin subdir layout (lib/paraview-X.Y/plugins vs.
# lib/x86_64-linux-gnu/... vs. share/...) isn't stable, so search broadly and
# dump diagnostics if nothing matches.
set +x
TTK_PLUGIN="$(find "${PARAVIEW_PREFIX}" -name 'TopologyToolKit*.so' 2>/dev/null | head -1)"
if [ -z "${TTK_PLUGIN}" ]; then
    echo "ERROR: TopologyToolKit*.so not found under ${PARAVIEW_PREFIX}" >&2
    echo >&2
    echo "Any file with TTK / topology in the name:" >&2
    find "${PARAVIEW_PREFIX}" \( -iname '*ttk*' -o -iname '*topology*' \) 2>/dev/null >&2 || true
    echo >&2
    echo "ParaView plugin directories under prefix:" >&2
    find "${PARAVIEW_PREFIX}" -type d -name plugins 2>/dev/null >&2 || true
    exit 1
fi
echo "TTK plugin found: ${TTK_PLUGIN}"
set -x
