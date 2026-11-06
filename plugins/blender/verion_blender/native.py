"""Finds the native `verion` extension and checks that it is the version this add-on expects.

An installed extension package carries the wheel, which Blender puts on `sys.path`. From a source
checkout the extension is looked up in `$VERION_NATIVE_PATH` and in `<repo>/target/py`, where
`scripts/py_test.sh` unpacks the wheel it builds.
"""
import os
import sys

# Must equal `ABI_VERSION` in crates/verion-py/src/lib.rs.
EXPECTED_ABI = 1


class NativeError(RuntimeError):
    """The native extension is missing or does not match this add-on."""


_module = None


def _dev_paths():
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.abspath(os.path.join(here, "..", "..", ".."))
    for p in (os.environ.get("VERION_NATIVE_PATH"), os.path.join(repo, "target", "py")):
        if p and os.path.isdir(p):
            yield p


def load():
    global _module
    if _module is not None:
        return _module
    try:
        import verion
    except ImportError:
        for p in _dev_paths():
            if p not in sys.path:
                sys.path.append(p)
        try:
            import verion
        except ImportError as e:
            raise NativeError(
                f"The Verion native extension could not be loaded ({e}). "
                "Reinstall the add-on for this platform."
            ) from e
    abi = getattr(verion, "ABI_VERSION", None)
    if abi != EXPECTED_ABI:
        raise NativeError(
            f"The Verion native extension has ABI {abi}, this add-on needs {EXPECTED_ABI}. "
            "Update both together."
        )
    _module = verion
    lib = blender_oidn()
    if lib:
        verion.set_oidn_library(lib)
    return verion


def blender_oidn():
    """Blender's own copy of Open Image Denoise (it ships its GPU modules too), or None."""
    import bpy

    root = os.path.dirname(bpy.app.binary_path)
    for p in (
        os.path.join(root, "..", "Resources", "lib", "libOpenImageDenoise.dylib"),  # macOS
        os.path.join(root, "blender.shared", "OpenImageDenoise.dll"),                # Windows (4.5+)
        os.path.join(root, "OpenImageDenoise.dll"),                                  # Windows (older)
        os.path.join(root, "lib", "libOpenImageDenoise.so.2"),                       # Linux
        os.path.join(root, "lib", "libOpenImageDenoise.so"),
    ):
        if os.path.exists(p):
            return os.path.normpath(p)
    return None


def available():
    """(ok, message) without raising, for the UI."""
    try:
        load()
        return True, ""
    except NativeError as e:
        return False, str(e)
