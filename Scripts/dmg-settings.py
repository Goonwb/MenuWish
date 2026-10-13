"""Finder layout for the drag-to-Applications installer (used by dmgbuild)."""

files = [(defines["app"], "MenuWish.app")]
symlinks = {"Applications": "/Applications"}
background = defines["background"]
icon = defines["icon"]
format = "UDZO"
filesystem = "HFS+"
# Leave room for Finder's title/path/status bars when user preferences show them.
window_rect = ((180, 160), (660, 400))
icon_locations = {"MenuWish.app": (180, 220), "Applications": (480, 220)}
icon_size = 104
text_size = 14
default_view = "icon-view"
arrange_by = None
grid_spacing = 80
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
# Do not add FinderInfo to a signed app just to hide its suffix: that breaks
# codesign --verify --strict after installation.
hide_extensions = []
include_icon_view_settings = True
include_list_view_settings = False
