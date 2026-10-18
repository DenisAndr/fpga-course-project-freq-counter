# Збірка Vitis: платформа MicroBlaze з freq_sys.xsa + застосунок sw/freq_main.c.
# Запуск з кореня репозиторію (після build_system.tcl):  vitis -s scripts/build_vitis.py
import os
import vitis

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace("\\", "/")
ws   = root + "/vitis"
xsa  = root + "/freq_sys.xsa"
src  = root + "/sw"

client = vitis.create_client()
client.set_workspace(path=ws)

platform = client.create_platform_component(
    name="platform", hw_design=xsa, os="standalone",
    cpu="microblaze_0", domain_name="standalone_microblaze_0", compiler="gcc")
platform = client.get_component(name="platform")
print("platform build:", platform.build())

client.create_app_component(
    name="app_component",
    platform=ws + "/platform/export/platform/platform.xpfm",
    domain="standalone_microblaze_0")
comp = client.get_component(name="app_component")
comp.import_files(from_loc=src, files=["freq_main.c"], dest_dir_in_cmp="src", is_skip_copy_sources=False)
print("app build:", comp.build())

vitis.dispose()
