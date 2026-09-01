#!/bin/tcsh -f
#-------------------------------------------
# qflow exec script for project /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave
#-------------------------------------------

# /usr/local/share/qflow/scripts/yosys.sh /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave/source/tt_um_cleave.v || exit 1
# /usr/local/share/qflow/scripts/graywolf.sh -d /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
# /usr/local/share/qflow/scripts/opensta.sh  /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
/usr/local/share/qflow/scripts/qrouter.sh /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
# /usr/local/share/qflow/scripts/opensta.sh  -d /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
# /usr/local/share/qflow/scripts/magic_db.sh /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
# /usr/local/share/qflow/scripts/magic_drc.sh /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
# /usr/local/share/qflow/scripts/netgen_lvs.sh /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
# /usr/local/share/qflow/scripts/magic_gds.sh /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
# /usr/local/share/qflow/scripts/cleanup.sh /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
# /usr/local/share/qflow/scripts/cleanup.sh -p /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
# /usr/local/share/qflow/scripts/magic_view.sh /mnt/c/Users/Nitro/Desktop/ASIC/Projects/cleave tt_um_cleave || exit 1
