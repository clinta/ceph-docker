#!/usr/bin/env bash
set -xe


# FUNCTIONS
function create_disk {
    local node_number
    local disk_image=${1}
    local storage_data_dir=${2}
    local loopback_disk_size=${3}

    # Create a loopback disk and format it to XFS.
    if [[ -e ${disk_image} ]]; then
        if egrep -q ${storage_data_dir} /proc/mounts; then
            sudo umount ${storage_data_dir}/drives/sdb1
            sudo rm -f ${disk_image}
        fi
    fi

    sudo mkdir -p ${storage_data_dir}/drives/images

    sudo truncate -s ${loopback_disk_size} ${disk_image}

    # Make a fresh XFS filesystem. Use bigger inodes so xattr can fit in
    # a single inode. Keeping the default inode size (256) will result in multiple
    # inodes being used to store xattr. Retrieving the xattr will be slower
    # since we have to read multiple inodes. This statement is true for both
    # Swift and Ceph.
    sudo mkfs.xfs -f -i size=1024 ${disk_image}

    # Mount the disk with mount options to make it as efficient as possible
    if ! egrep -q ${storage_data_dir} /proc/mounts; then
        sudo mount -t xfs -o loop,noatime,nodiratime,nobarrier,logbufs=8  \
            ${disk_image} ${storage_data_dir}
    fi
}

function do_aio_conf {
  # set pools replica size to 1 since we only have a single osd
  # also use a really low pg count
  echo "osd pool default size = 1" >> /etc/ceph/ceph.conf
  echo "osd pool default pg num = 8" >> /etc/ceph/ceph.conf
  echo "osd pool default pgp num = 8" >> /etc/ceph/ceph.conf
}

function bootstrap_osd {
  mkdir -p /var/lib/ceph/osd/ceph-0
  chown -R 64045:64045 /var/lib/ceph/osd/*
  docker exec ceph-mon ceph osd create
  docker exec ceph-mon ceph-osd -i 0 --mkfs
  docker exec ceph-mon ceph auth get-or-create osd.0 osd 'allow *' mon 'allow profile osd' -o /var/lib/ceph/osd/ceph-0/keyring
  docker exec ceph-mon ceph osd crush add 0 1 root=default host=$(hostname -s)
  docker exec ceph-mon ceph-osd -i 0 -k /var/lib/ceph/osd/ceph-0/keyring
}


# MAIN
create_disk /tmp/ceph.img /var/lib/ceph 20
do_aio_conf
bootstrap_osd
