"""Build the image and validate the mounted app before it is compressed."""

import os
import subprocess
import sys

import dmgbuild
from ds_store import DSStore, DSStoreEntry

app, background, icon, bookmark_tool, version, output = sys.argv[1:]
mounted = None


def mounted_hook(mount_point, options):
    global mounted
    mounted = mount_point
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", os.path.join(mounted, "MenuWish.app")],
        check=True,
    )


def build_event(event):
    if event.get("type") != "operation::finished" or event.get("operation") != "dsstore::create":
        return
    image = os.path.join(mounted, ".background.tiff")
    bookmark = subprocess.check_output([bookmark_tool, image])
    with DSStore.open(os.path.join(mounted, ".DS_Store"), "r+") as store:
        # Preserve Foundation's bytes instead of re-encoding through mac_alias.
        store.insert(DSStoreEntry(".", b"pBBk", b"blob", bookmark))


dmgbuild.build_dmg(
    output,
    "MenuWish " + version,
    settings_file=os.path.join(os.path.dirname(__file__), "dmg-settings.py"),
    settings={"create_hook": mounted_hook},
    defines={"app": app, "background": background, "icon": icon},
    callback=build_event,
)
