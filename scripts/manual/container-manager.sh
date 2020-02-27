#!/bin/bash
set -x

# We need to put the rootfs somewhere where we can modify some
# parts of the content on first boot (namely file permissions).
# Other than that nothing should ever modify the content of the
# rootfs.

DATA_PATH=/var/lib/anbox
ANDROID_IMG=$DATA_PATH/android.img

if [ "$(id -u)" != 0 ]; then
	echo "ERROR: You need to run the container manager as root"
	exit 1
fi

if [ ! -e "$ANDROID_IMG" ]; then
	echo "ERROR: android image does not exist"
	exit 1
fi

# Re-exec outside of apparmor confinement
if [ -d /sys/kernel/security/apparmor ] && [ "$(cat /proc/self/attr/current)" != "unconfined" ]; then
	exec /usr/sbin/aa-exec -p unconfined -- "$0" "$@"
fi

start() {
	# Make sure our setup path for the container rootfs
	# is present as lxc is statically configured for
	# this path.
	mkdir -p "$DATA_PATH/lxc"

	# call restart to make sure the resident network-up can be cleaned
	./anbox-bridge.sh restart

	# Ensure FUSE support for user namespaces is enabled
	echo Y | tee /sys/module/fuse/parameters/userns_mounts || echo "WARNING: kernel doesn't support fuse in user namespaces"

	modprobe binder_linux
	modprobe ashmem_linux

	# Ensure we have binderfs mounted when our kernel supports it
	if cat /proc/filesystems | grep -q binder ; then
		mkdir -p $DATA_PATH/binderfs
		# Remove old mounts so that we start fresh without any devices allocated
		if cat /proc/mounts | grep -q "binder $DATA_PATH/binderfs" ; then
			umount $DATA_PATH/binderfs
		fi
		mount -t binder none $DATA_PATH/binderfs
	fi

	anbox container-manager \
		--data-path="$DATA_PATH" \
		--android-image="$ANDROID_IMG" \
		--daemon \
		--privileged --use-rootfs-overlay&
}

stop() {
	./anbox-bridge.sh stop
}

case "$1" in
	start)
		start
		;;
	stop)
		stop
		;;
	*)
		echo "ERROR: Unknown command '$1'"
		exit 1
		;;
esac
