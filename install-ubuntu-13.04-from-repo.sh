function pre {
	get_ntpdate
	check_if_partitioned
	remove_all_partitions
	create_one_partition ext4
	mount_partition "-t ext4"
}

function post {
	umount_partition
}

function download_and_install {
	# Disable terminal blanking on HDMI port (/dev/tty1)
	echo -e '\033[9;0]\033[14;0]' > /dev/tty1
	echo "Grabbing Ubuntu core base image"
	curl http://cdimage.ubuntu.com/ubuntu-core/releases/13.04/release/ubuntu-core-13.04-core-armhf.tar.gz | /usr/bin/tar --overwrite -zx -C $ROOTFS_DIR
	mount -o bind /sys/ $ROOTFS_DIR/sys/
	mount -o bind /dev/ $ROOTFS_DIR/dev/
	mount -o bind /dev/pts/ $ROOTFS_DIR/dev/pts/
	mount -o bind /proc/ $ROOTFS_DIR/proc/

	# Create the boot.scr u-boot script
	cat > $ROOTFS_DIR/boot/boot.txt << EOF
setenv bootargs 'console=ttyS0,115200n8 vmalloc=384M root=/dev/mmcblk0p1 video=dovefb:lcd0:1920x1080-32@60-edid clcd.lcd0_enable=1'
ext4load mmc 0:1 0x02000000 /boot/uImage
bootm
EOF
	echo "Creating boot.scr script"
	mkimage -T script -C none -n 'CuBox' -d $ROOTFS_DIR/boot/boot.txt $ROOTFS_DIR/boot/boot.scr

	# Get the kernel and modules
	export KERN_VER=3.6.9-00797-g0d7ee41
	echo "Downloading kernel version $KERN_VER"
	curl http://download.solid-run.com/pub/solidrun/cubox/kernel/bin/$KERN_VER/uImage-$KERN_VER > $ROOTFS_DIR/boot/uImage-$KERN_VER
	ln -f -s uImage-$KERN_VER $ROOTFS_DIR/boot/uImage
	echo "Downloading kernel modules"
	curl http://download.solid-run.com/pub/solidrun/cubox/kernel/bin/$KERN_VER/modules-$KERN_VER.tar.xz | /usr/bin/tar --overwrite -Jx -C $ROOTFS_DIR

	echo "Setting up ttyS0 serial port terminal"
	cat > $ROOTFS_DIR/etc/init/ttyS0.conf << EOF
# ttyS0 - getty
#
# This service maintains a getty on ttyS0 from the point the system is
# started until it is shut down again.

start on stopped rc RUNLEVEL=[2345] and (
            not-container or
            container CONTAINER=lxc or
            container CONTAINER=lxc-libvirt)

stop on runlevel [!2345]

respawn
exec /sbin/getty -8 115200 ttyS0
EOF

	echo "Setting up root password (cubox)"
	echo -e "cubox\ncubox" | chroot $ROOTFS_DIR passwd
	# Get DNS settings
	cp /etc/resolv.conf $ROOTFS_DIR/etc/
	# Setup CuBox repo
	cat > $ROOTFS_DIR/etc/apt/sources.list.d/cubox.list << EOF
deb http://download.solid-run.com/pub/solidrun/cubox/repo/debian cubox main
deb-src http://download.solid-run.com/pub/solidrun/cubox/repo/debian cubox main
EOF
	# Setup localhost and cubox
	cat > $ROOTFS_DIR/etc/hosts << EOF
127.0.0.1	localhost
127.0.1.1	cubox
EOF

	# Set hostname
	# chroot $ROOTFS_DIR/ hostname cubox
	echo cubox > $ROOTFS_DIR/etc/hostname

	# Get the universe and restricted to the sources.list
	cat $ROOTFS_DIR/etc/apt/sources.list | sed '/##/!s/# d/d/' > /tmp/sources.list
	mv /tmp/sources.list $ROOTFS_DIR/etc/apt/sources.list

	chroot $ROOTFS_DIR apt-get update
	# Install CuBox GLES drivers and Dove xorg driver
	chroot $ROOTFS_DIR apt-get install -y --force-yes marvell-libgfx xserver-xorg-video-dove
	# Install CuBox specific xorg.conf and alsa config files
	chroot $ROOTFS_DIR apt-get install --force-yes -y cubox-alsa-conf xorg-dove-x11-conf

	# Essentials
	chroot $ROOTFS_DIR apt-get install -y apt-utils dialog lm-sensors iputils-ping net-tools openssh-server less
	# Workaround ubuntu upstart issue.
	mv $ROOTFS_DIR/sbin/initctl $ROOTFS_DIR/sbin/initctl.orig
	ln -s /bin/true $ROOTFS_DIR/sbin/initctl

	# Install a wordlist, otherwise dictionaries-common fails.
	chroot $ROOTFS_DIR apt-get install -y -qq wamerican-insane

	# Generate localtes
	chroot $ROOTFS_DIR locale-gen en_US en_US.UTF-8
	chroot $ROOTFS_DIR dpkg-reconfigure locales 
	echo "Base rootfs is installed. Click any key to go to next menu"
	read
	# Now provide more options what else to install
	TEMP=`mktemp`
	while [ 1 ]; do
		dialog --menu "What else ?" 40 120 120 "1" "Install full Xubuntu desktop (~1.2GB)" "2" "Install slim+Awesome window manager (~200MB)" "3" "Install gstreamer and vmeta drivers" "4" "Create user cubox (password cubox)" "D" "Done. Wrapup and exit to main menu" 2> $TEMP
		CHC=`cat $TEMP`
		if [ $CHC == "1" ]; then
			# Install xubuntu-desktop
			echo "Installing full Xunbut-desktop. Will download and install about 1.2GB of packages"
			chroot $ROOTFS_DIR apt-get install -y xubuntu-desktop
		fi
		if [ $CHC == "2" ]; then
			# Install slim+awesome and other packages that are typically needed
			echo "Installing slim login manager, awesome window manager and other required packages."
			chroot $ROOTFS_DIR apt-get install -y slim awesome xserver-xorg isc-dhcp-client xterm console-setup nano x11-apps
			chroot $ROOTFS_DIR apt-get install --no-install-recommends -y network-manager
			echo "auto eth0" >> $ROOTFS_DIR/etc/network/interfaces
			echo "iface eth0 inet dhcp" >> $ROOTFS_DIR/etc/network/interfaces

		fi
		if [ $CHC == "3" ]; then
			# Install awesome and xserver-xorg. Probably other packages are missing
			chroot $ROOTFS_DIR apt-get install --force-yes -y gstreamer0.10-plugins-bmmxv gstreamer0.10-plugins-marvell gstreamer-tools gstreamer0.10-plugins-good
		fi
		if [ $CHC == "4" ]; then
			# Create user cubox and it to groups audio and plugdev
			echo -e "cubox\ncubox\n\n\n\n\n\nY\n" | chroot $ROOTFS_DIR adduser cubox
			chroot $ROOTFS_DIR addgroup cubox audio
			chroot $ROOTFS_DIR addgroup cubox plugdev
		fi
		if [ $CHC == "D" ]; then
			# Now install xubuntu-desktop
			break
		fi
		echo "Done. Press any key to return to menu"
	done

	# Cleanup of the upstart issue
	rm $ROOTFS_DIR/sbin/initctl
	mv $ROOTFS_DIR/sbin/initctl.orig $ROOTFS_DIR/sbin/initctl

	# TODO Cleanup downloaded packages

	# Unmount
	sync
	umount $ROOTFS_DIR/sys/
	umount $ROOTFS_DIR/dev/pts/
	sync
	umount $ROOTFS_DIR/dev/
	sync
	umount $ROOTFS_DIR/proc/
	sync
}

pre
download_and_install
echo "Installation done. Click any key"
read
post
