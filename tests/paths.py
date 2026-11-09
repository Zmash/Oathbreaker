import os

HERE = os.path.dirname(os.path.abspath(__file__))
ADDON = os.path.join(HERE, "..", "Oathbreaker")
ZYGOR = os.environ.get(
    "ZYGOR_DIR",
    r"D:\WoW\World of Warcraft\_forever_\Interface\AddOns\ZygorGuidesViewerForever",
)
