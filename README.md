cubox-installer-scripts
=======================

This git repo holds installer scripts (plugins) to the CuBox Installer.
When the CuBox installers is booted from a USB thumb drive, it loads the the
file called distr.list from this repo; which is a distribution list file.

The distribution list is parsed by the CuBox installer (install.sh main script)
and then shows a dialog menu according to that list where the user can choose
from.

Each line on that distribution list can hold a link to a script like the
scripts in this repository. For instance u-boot script is -
https://github.com/rabeeh/cubox-installer-scripts/raw/master/install-u-boot

Each script is only downloaded when the user chooses a specific item from the list,
then that script is executed via 'source' bash script.

Simple scripts can be operating the install.sh (partition, ntp, format etc...)
More complex scripts can show submenus to shows even more advanced things.

Please contribute to the CuBox project with more scripts by cloning this repo
and then ask for pull request on github.

SolidRun team.
