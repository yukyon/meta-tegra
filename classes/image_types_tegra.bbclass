inherit image_types image_types_cboot python3native perlnative

IMAGE_TYPES += "tegraflash"

IMAGE_ROOTFS_ALIGNMENT ?= "4"

def tegra_default_rootfs_size(d):
    partsize = int(d.getVar('ROOTFSPART_SIZE')) // 1024
    extraspace = eval(d.getVar('IMAGE_ROOTFS_EXTRA_SPACE'))
    return str(partsize - extraspace)

IMAGE_ROOTFS_SIZE ?= "${@tegra_default_rootfs_size(d)}"

IMAGE_UBOOT ??= "u-boot"
INITRD_IMAGE ??= ""
KERNEL_ARGS ??= ""
TEGRA_SIGNING_ARGS ??= ""
TEGRA_SIGNING_ENV ??= ""
TEGRA_SIGNING_EXCLUDE_TOOLS ??= ""
TEGRA_SIGNING_EXTRA_DEPS ??= ""
TEGRA_BUPGEN_SPECS ??= "boardid=${TEGRA_BOARDID};fab=${TEGRA_FAB};boardrev=${TEGRA_BOARDREV};chiprev=${TEGRA_CHIPREV}"

DTBFILE ?= "${@os.path.basename(d.getVar('KERNEL_DEVICETREE').split()[0])}"
LNXFILE ?= "boot.img"
LNXSIZE ?= "83886080"
APPFILE ?= "${@'${IMAGE_BASENAME}.${IMAGE_TEGRAFLASH_FS_TYPE}' if d.getVar('TEGRA_SPIFLASH_BOOT') == '1' else '${IMAGE_BASENAME}.img'}"

IMAGE_TEGRAFLASH_FS_TYPE ??= "ext4"
IMAGE_TEGRAFLASH_ROOTFS ?= "${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.${IMAGE_TEGRAFLASH_FS_TYPE}"
IMAGE_TEGRAFLASH_KERNEL ?= "${DEPLOY_DIR_IMAGE}/${@'${IMAGE_UBOOT}-${MACHINE}.bin' if '${IMAGE_UBOOT}' != '' else '${KERNEL_IMAGETYPE}-initramfs-${MACHINE}.cboot'}"

BL_IS_CBOOT = "${@'1' if d.getVar('PREFERRED_PROVIDER_virtual/bootloader').startswith('cboot') else '0'}"
TEGRA_SPIFLASH_BOOT ??= ""

CBOOTFILENAME = "cboot.bin"
CBOOTFILENAME_tegra194 = "cboot_t194.bin"
TOSIMGFILENAME = "tos-trusty.img"
TOSIMGFILENAME_tegra194 = "tos-trusty_t194.img"
TOSIMGFILENAME_tegra210 = "tos-mon-only.img"

BUP_PAYLOAD_DIR = "payloads_t${@d.getVar('NVIDIA_CHIP')[2:]}x"
FLASHTOOLS_DIR = "${SOC_FAMILY}-flash"
FLASHTOOLS_DIR_tegra194 = "tegra186-flash"

# Override this function if you need to add
# customization after the default files are
# copied/symlinked into the working directory
# and before processing begins.
tegraflash_custom_pre() {
    :
}

# Override these functions to run a custom code signing
# step, such as packaging the flash/BUP contents and
# sending them to a remote code signing server.
#
# -- Function for signing a full tegraflash package --
#
# By default, if TEGRA_SIGNING_ARGS is defined, this function
# will run doflash.sh --no-flash to sign the binaries, then
# replace the doflash.sh script with the flashcmd.txt script
# that tegraflash.py generates, which will run tegraflash.py
# with the necessary arguments to send the signed binaries
# to the device.
tegraflash_custom_sign_pkg() {
    if [ -n "${TEGRA_SIGNING_ARGS}" ]; then
        ${TEGRA_SIGNING_ENV} ./doflash.sh --no-flash ${TEGRA_SIGNING_ARGS}
        [ -e flashcmd.txt ] || bbfatal "No flashcmd.txt generated by signing step"
        rm doflash.sh
        mv flashcmd.txt doflash.sh
        chmod +x doflash.sh
    fi
}

# -- Function for BUP signing/creation --
# Note that this is *always* run. If no key is provided, binaries
# will be signed with a null key.
tegraflash_custom_sign_bup() {
    ./doflash.sh ${TEGRA_SIGNING_ARGS}
}

# Override this function if you need to add
# customization after other processing is done
# but before the zip package is created.
tegraflash_custom_post() {
    :
}

tegraflash_create_flash_config() {
    :
}

tegraflash_create_flash_config_tegra210() {
    local destdir="$1"
    local lnxfile="$2"
    local rootfsimg="$3"
    local bupgen="$4"
    local apptag

    if [ -n "$bupgen" ]; then
        apptag="/APPFILE/d"
    else
	apptag="s,APPFILE,$3,"
    fi
    cat "${STAGING_DATADIR}/tegraflash/${PARTITION_LAYOUT_TEMPLATE}" | sed \
        -e"s,EBTFILE,${CBOOTFILENAME}," \
        -e"s,LNXFILE,$lnxfile," \
        -e"/NCTFILE/d" -e"s,NCTTYPE,data," \
        -e"/SOSFILE/d" \
        -e"s,NXC,NVC," -e"s,NVCTYPE,bootloader," -e"s,NVCFILE,nvtboot.bin," \
        -e"s,MPBTYPE,data," -e"/MPBFILE/d" \
        -e"s,MBPTYPE,data," -e"/MBPFILE/d" \
        -e"s,BXF,BPF," -e"s,BPFFILE,sc7entry-firmware.bin," \
        -e"/BPFDTB-FILE/d" \
        -e"s,WX0,WB0," -e"s,WB0TYPE,WB0," -e"s,WB0FILE,warmboot.bin," \
        -e"s,TXS,TOS," -e"s,TOSFILE,${TOSIMGFILENAME}," \
        -e"s,EXS,EKS," -e"s,EKSFILE,eks.img," \
        -e"s,FBTYPE,data," -e"/FBFILE/d" \
        -e"s,DXB,DTB," \
        -e"$apptag" -e"s,APPSIZE,${ROOTFSPART_SIZE}," \
        -e"s,TXC,TBC," -e"s,TBCTYPE,bootloader," -e"s,TBCFILE,nvtboot_cpu.bin," \
        -e"s,EFISIZE,67108864," -e"/EFIFILE/d" \
        -e"s,RECNAME,recovery," -e"s,RECSIZE,66060288," -e"s,RECDTB-NAME,recovery-dtb," -e"s,BOOTCTRLNAME,kernel-bootctrl," \
        -e"s,PPTSIZE,16896," \
        -e"s,APPUUID,," \
        > $destdir/flash.xml.in
}

tegraflash_create_flash_config_tegra186() {
    local destdir="$1"
    local lnxfile="$2"
    local rootfsimg="$3"
    local bupgen="$4"
    local apptag

    if [ -n "$bupgen" ]; then
        apptag="/APPFILE/d"
    else
	apptag="s,APPFILE,$3,"
    fi

    # The following sed expression are derived from xxx_TAG variables
    # in the L4T flash.sh script.  Tegra186-specific.
    cat "${STAGING_DATADIR}/tegraflash/${PARTITION_LAYOUT_TEMPLATE}" | sed \
        -e"s,LNXFILE,$lnxfile," \
        -e"s,LNXSIZE,${LNXSIZE}," -e"s,LNXNAME,kernel," \
        -e"/SOSFILE/d" \
        -e"s,MB2TYPE,mb2_bootloader," -e"s,MB2FILE,nvtboot.bin," -e"s,MB2NAME,mb2," \
        -e"s,MPBTYPE,mts_preboot," -e"s,MPBFILE,preboot_d15_prod_cr.bin," -e"s,MPBNAME,mts-preboot," \
        -e"s,MBPTYPE,mts_bootpack," -e"s,MBPFILE,mce_mts_d15_prod_cr.bin," -e"s,MBPNAME,mts-bootpack," \
        -e"s,MB1TYPE,mb1_bootloader," -e"s,MB1FILE,mb1_prod.bin," -e"s,MB1NAME,mb1," \
        -e"s,DRAMECCTYPE,dram_ecc," -e"s,DRAMECCFILE,dram-ecc.bin," -e"s,DRAMECCNAME,dram-ecc-fw," \
        -e"s,BADPAGETYPE,black_list_info," -e"s,BADPAGEFILE,badpage.bin," -e"s,BADPAGENAME,badpage-fw," \
        -e"s,BPFFILE,bpmp.bin," -e"s,BPFNAME,bpmp-fw," -e"s,BPFSIGN,true," \
        -e"s,BPFDTB-NAME,bpmp-fw-dtb," -e"s,BPMPDTB-SIGN,true," \
        -e"s,TBCFILE,${CBOOTFILENAME}," -e"s,TBCTYPE,bootloader," -e"s,TBCNAME,cpu-bootloader," \
        -e"s,TBCDTB-NAME,bootloader-dtb," -e"s,TBCDTB-FILE,${DTBFILE}," \
        -e"s,SCEFILE,camera-rtcpu-sce.img," -e"s,SCENAME,sce-fw," -e"s,SCESIGN,true," \
        -e"s,SPEFILE,spe.bin," -e"s,SPENAME,spe-fw," -e"s,SPETYPE,spe_fw," \
        -e"s,WB0TYPE,WB0," -e"s,WB0FILE,warmboot.bin," -e"s,SC7NAME,sc7," \
        -e"s,TOSFILE,${TOSIMGFILENAME}," -e"s,TOSNAME,secure-os," \
        -e"s,EKSFILE,eks.img," \
        -e"s,FBTYPE,data," -e"s,FBSIGN,false," -e"/FBFILE/d" \
        -e"s,KERNELDTB-NAME,kernel-dtb," -e"s,KERNELDTB-FILE,${DTBFILE}," \
        -e"$apptag" -e"s,APPSIZE,${ROOTFSPART_SIZE}," \
        -e"s,RECNAME,recovery," -e"s,RECSIZE,66060288," -e"s,RECDTB-NAME,recovery-dtb," -e"s,BOOTCTRLNAME,kernel-bootctrl," \
        -e"/RECFILE/d" -e"/RECDTB-FILE/d" -e"/BOOTCTRL-FILE/d" \
        -e"s,PPTSIZE,2097152," \
        -e"s,APPUUID,," \
        > $destdir/flash.xml.in
}

tegraflash_create_flash_config_tegra194() {
    local destdir="$1"
    local lnxfile="$2"
    local rootfsimg="$3"
    local bupgen="$4"
    local apptag

    if [ -n "$bupgen" ]; then
        apptag="/APPFILE/d"
    else
	apptag="s,APPFILE,$3,"
    fi

    # The following sed expression are derived from xxx_TAG variables
    # in the L4T flash.sh script.  Tegra194-specific.
    # Note that the blank before DTB_FILE is important, to
    # prevent BPFDTB_FILE from being matched.
    cat "${STAGING_DATADIR}/tegraflash/${PARTITION_LAYOUT_TEMPLATE}" | sed \
        -e"s,LNXFILE,$lnxfile," -e"s,LNXSIZE,${LNXSIZE}," \
        -e"s,TEGRABOOT,nvtboot_t194.bin," \
        -e"s,MTSPREBOOT,preboot_c10_prod_cr.bin," \
        -e"s,MTS_MCE,mce_c10_prod_cr.bin," \
        -e"s,MTSPROPER,mts_c10_prod_cr.bin," \
        -e"s,MB1FILE,mb1_t194_prod.bin," \
        -e"s,BPFFILE,bpmp_t194.bin," \
        -e"s,TBCFILE,${CBOOTFILENAME}," \
        -e"s,TBCDTB-FILE,${DTBFILE}," \
        -e"s,CAMERAFW,camera-rtcpu-rce.img," \
        -e"s,SPEFILE,spe_t194.bin," \
        -e"s,WB0BOOT,warmboot_t194_prod.bin," \
        -e"s,TOSFILE,${TOSIMGFILENAME}," \
        -e"s,EKSFILE,eks.img," \
        -e"s, DTB_FILE, ${DTBFILE}," \
        -e"s,CBOOTOPTION_FILE,cbo.dtb," \
        -e"s,RECNAME,recovery," -e"s,RECSIZE,66060288," -e"s,RECDTB-NAME,recovery-dtb," -e"s,BOOTCTRLNAME,kernel-bootctrl," \
        -e"/RECFILE/d" -e"/RECDTB-FILE/d" -e"/BOOTCTRL-FILE/d" \
        -e"$apptag" -e"s,APPSIZE,${ROOTFSPART_SIZE}," \
        -e"s,APPUUID,," \
        > $destdir/flash.xml.in
}

BOOTFILES = ""
BOOTFILES_tegra210 = "\
    bmp.blob \
    eks.img \
    nvtboot_recovery.bin \
    nvtboot.bin \
    nvtboot_cpu.bin \
    warmboot.bin \
    rp4.blob \
    sc7entry-firmware.bin \
"
BOOTFILES_tegra186 = "\
    adsp-fw.bin \
    bmp.blob \
    bpmp.bin \
    camera-rtcpu-sce.img \
    dram-ecc.bin \
    eks.img \
    mb1_prod.bin \
    mb1_recovery_prod.bin \
    mce_mts_d15_prod_cr.bin \
    nvtboot_cpu.bin \
    nvtboot_recovery.bin \
    nvtboot_recovery_cpu.bin \
    preboot_d15_prod_cr.bin \
    slot_metadata.bin \
    spe.bin \
    nvtboot.bin \
    warmboot.bin \
    minimal_scr.cfg \
    mobile_scr.cfg \
    emmc.cfg \
"

BOOTFILES_tegra194 = "\
    adsp-fw.bin \
    bmp.blob \
    bpmp_t194.bin \
    camera-rtcpu-rce.img \
    eks.img \
    mb1_t194_prod.bin \
    nvtboot_applet_t194.bin \
    nvtboot_t194.bin \
    preboot_c10_prod_cr.bin \
    mce_c10_prod_cr.bin \
    mts_c10_prod_cr.bin \
    nvtboot_cpu_t194.bin \
    nvtboot_recovery_t194.bin \
    nvtboot_recovery_cpu_t194.bin \
    preboot_d15_prod_cr.bin \
    slot_metadata.bin \
    spe_t194.bin \
    warmboot_t194_prod.bin \
    xusb_sil_rel_fw \
    cbo.dtb \
"

create_tegraflash_pkg() {
    :
}

create_tegraflash_pkg_tegra210() {
    PATH="${STAGING_BINDIR_NATIVE}/tegra210-flash:${PATH}"
    rm -rf "${WORKDIR}/tegraflash"
    mkdir -p "${WORKDIR}/tegraflash"
    oldwd=`pwd`
    cd "${WORKDIR}/tegraflash"
    ln -sf "${STAGING_DATADIR}/tegraflash/bsp_version" .
    ln -s "${STAGING_DATADIR}/tegraflash/${MACHINE}.cfg" .
    ln -s "${IMAGE_TEGRAFLASH_KERNEL}" ./${LNXFILE}
    cp ${STAGING_DATADIR}/tegraflash/flashvars .
    for f in ${KERNEL_DEVICETREE}; do
	dtbf=`basename $f`
	cp -L "${DEPLOY_DIR_IMAGE}/$dtbf" ./
	if [ -n "${KERNEL_ARGS}" ]; then
            fdtput -t s ./$dtbf /chosen bootargs "${KERNEL_ARGS}"
	elif fdtget -t s ./$dtbf /chosen bootargs >/dev/null 2>&1; then
            fdtput -d ./$dtbf /chosen bootargs
	fi
    done
    ln -sf "${DEPLOY_DIR_IMAGE}/cboot-${MACHINE}.bin" ./${CBOOTFILENAME}
    ln -sf "${DEPLOY_DIR_IMAGE}/tos-${MACHINE}.img" ./${TOSIMGFILENAME}
    for f in ${BOOTFILES}; do
        ln -s "${STAGING_DATADIR}/tegraflash/$f" .
    done
    if [ -n "${NVIDIA_BOARD_CFG}" ]; then
        ln -s "${STAGING_DATADIR}/tegraflash/board_config_${MACHINE}.xml" .
        boardcfg=board_config_${MACHINE}.xml
    else
        boardcfg=
    fi

    [ "${TEGRA_SIGNING_EXCLUDE_TOOLS}" = "1" ] || cp -R ${STAGING_BINDIR_NATIVE}/tegra210-flash/* .
    tegraflash_custom_pre
    ln -s "${IMAGE_TEGRAFLASH_ROOTFS}" ./${IMAGE_BASENAME}.${IMAGE_TEGRAFLASH_FS_TYPE}
    # for tegra210, the flash helper script puts APPFILE in the XML
    tegraflash_create_flash_config "${WORKDIR}/tegraflash" ${LNXFILE} APPFILE

    rm -f doflash.sh
    cat > doflash.sh <<END
#!/bin/sh
MACHINE=${MACHINE} ./tegra210-flash-helper.sh -B ${TEGRA_BLBLOCKSIZE} flash.xml.in ${DTBFILE} ${MACHINE}.cfg ${ODMDATA} "$boardcfg" ${LNXFILE} "${IMAGE_BASENAME}.${IMAGE_TEGRAFLASH_FS_TYPE}" "\$@"
END
    chmod +x doflash.sh
    if [ "${TEGRA_SPIFLASH_BOOT}" = "1" ]; then
        rm -f dosdcard.sh
        cat > dosdcard.sh <<END
#!/bin/sh
MACHINE=${MACHINE} ./tegra210-flash-helper.sh --sdcard -B ${TEGRA_BLBLOCKSIZE} -s ${TEGRAFLASH_SDCARD_SIZE} -b ${IMAGE_BASENAME} flash.xml.in ${DTBFILE} ${MACHINE}.cfg ${ODMDATA} "$boardcfg" ${LNXFILE} "${IMAGE_BASENAME}.${IMAGE_TEGRAFLASH_FS_TYPE}" "\$@"
END
        chmod +x dosdcard.sh
    fi
    tegraflash_custom_post
    tegraflash_custom_sign_pkg
    rm -f ${IMGDEPLOYDIR}/${IMAGE_NAME}.tegraflash.zip
    zip -r ${IMGDEPLOYDIR}/${IMAGE_NAME}.tegraflash.zip .
    ln -sf ${IMAGE_NAME}.tegraflash.zip ${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.tegraflash.zip
    cd $oldwd
}

create_tegraflash_pkg_tegra186() {
    local f
    PATH="${STAGING_BINDIR_NATIVE}/tegra186-flash:${PATH}"
    rm -rf "${WORKDIR}/tegraflash"
    mkdir -p "${WORKDIR}/tegraflash"
    oldwd=`pwd`
    cd "${WORKDIR}/tegraflash"
    ln -sf "${STAGING_DATADIR}/tegraflash/bsp_version" .
    ln -s "${STAGING_DATADIR}/tegraflash/${MACHINE}.cfg" .
    ln -s "${IMAGE_TEGRAFLASH_KERNEL}" ./${LNXFILE}
    cp -L "${DEPLOY_DIR_IMAGE}/${DTBFILE}" ./${DTBFILE}
    if [ -n "${KERNEL_ARGS}" ]; then
        fdtput -t s ./${DTBFILE} /chosen bootargs "${KERNEL_ARGS}"
    elif fdtget -t s ./${DTBFILE} /chosen bootargs >/dev/null 2>&1; then
        fdtput -d ./${DTBFILE} /chosen bootargs
    fi
    ln -sf "${DEPLOY_DIR_IMAGE}/cboot-${MACHINE}.bin" ./${CBOOTFILENAME}
    ln -sf "${DEPLOY_DIR_IMAGE}/tos-${MACHINE}.img" ./${TOSIMGFILENAME}
    for f in ${BOOTFILES}; do
        ln -s "${STAGING_DATADIR}/tegraflash/$f" .
    done
    cp ${STAGING_DATADIR}/tegraflash/flashvars .
    . ./flashvars
    for var in $FLASHVARS; do
        eval pat=$`echo $var`
        if [ -z "$pat" ]; then
            echo "ERR: missing variable: $var" >&2
            exit 1
        fi
        fnglob=`echo $pat | sed -e"s,@BPFDTBREV@,\*," -e"s,@BOARDREV@,\*," -e"s,@PMICREV@,\*," -e"s,@CHIPREV@,\*,"`
        for fname in ${STAGING_DATADIR}/tegraflash/$fnglob; do
            if [ ! -e $fname ]; then
               bbfatal "$var file(s) not found"
            fi
            ln -sf $fname ./
        done
    done
    [ "${TEGRA_SIGNING_EXCLUDE_TOOLS}" = "1" ] || cp -R ${STAGING_BINDIR_NATIVE}/tegra186-flash/* .
    dd if=/dev/zero of=badpage.bin bs=4096 count=1
    if [ -e ${STAGING_DATADIR}/tegraflash/odmfuse_pkc_${MACHINE}.xml ]; then
        cp ${STAGING_DATADIR}/tegraflash/odmfuse_pkc_${MACHINE}.xml ./odmfuse_pkc.xml
    fi
    tegraflash_custom_pre
    mksparse -v --fillpattern=0 "${IMAGE_TEGRAFLASH_ROOTFS}" ${IMAGE_BASENAME}.img
    tegraflash_create_flash_config "${WORKDIR}/tegraflash" ${LNXFILE} ${APPFILE}
    rm -f doflash.sh
    cat > doflash.sh <<END
#!/bin/sh
MACHINE=${MACHINE} ./tegra186-flash-helper.sh flash.xml.in ${DTBFILE} ${MACHINE}.cfg ${ODMDATA} ${LNXFILE} "\$@"
END
    chmod +x doflash.sh
    if [ -e ./odmfuse_pkc.xml ]; then
        cat > burnfuses.sh <<END
#!/bin/sh
MACHINE=${MACHINE} ./tegra186-flash-helper.sh --burnfuses flash.xml.in ${DTBFILE} ${MACHINE}.cfg ${ODMDATA} ${LNXFILE} "\$@"
END
	chmod +x burnfuses.sh
    fi
    tegraflash_custom_post
    tegraflash_custom_sign_pkg
    rm -f ${IMGDEPLOYDIR}/${IMAGE_NAME}.tegraflash.zip
    zip -r ${IMGDEPLOYDIR}/${IMAGE_NAME}.tegraflash.zip .
    ln -sf ${IMAGE_NAME}.tegraflash.zip ${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.tegraflash.zip
    cd $oldwd
}

create_tegraflash_pkg_tegra194() {
    local f
    PATH="${STAGING_BINDIR_NATIVE}/tegra186-flash:${PATH}"
    rm -rf "${WORKDIR}/tegraflash"
    mkdir -p "${WORKDIR}/tegraflash"
    oldwd=`pwd`
    cd "${WORKDIR}/tegraflash"
    ln -sf "${STAGING_DATADIR}/tegraflash/bsp_version" .
    ln -s "${STAGING_DATADIR}/tegraflash/${MACHINE}.cfg" .
    ln -s "${STAGING_DATADIR}/tegraflash/${MACHINE}-override.cfg" .
    ln -s "${IMAGE_TEGRAFLASH_KERNEL}" ./${LNXFILE}
    if [ -n "${KERNEL_ARGS}" ]; then
        cp -L "${DEPLOY_DIR_IMAGE}/${DTBFILE}" ./${DTBFILE}
        bootargs="`fdtget ./${DTBFILE} /chosen bootargs 2>/dev/null`"
        fdtput -t s ./${DTBFILE} /chosen bootargs "$bootargs ${KERNEL_ARGS}"
    else
        ln -s "${DEPLOY_DIR_IMAGE}/${DTBFILE}" ./${DTBFILE}
    fi
    ln -sf "${DEPLOY_DIR_IMAGE}/cboot-${MACHINE}.bin" ./${CBOOTFILENAME}
    ln -sf "${DEPLOY_DIR_IMAGE}/tos-${MACHINE}.img" ./${TOSIMGFILENAME}
    for f in ${BOOTFILES}; do
        ln -s "${STAGING_DATADIR}/tegraflash/$f" .
    done
    cp ${STAGING_DATADIR}/tegraflash/flashvars .
    for f in ${STAGING_DATADIR}/tegraflash/tegra19[4x]-*.cfg; do
        ln -s $f .
    done
    for f in ${STAGING_DATADIR}/tegraflash/tegra194-*-bpmp-*.dtb; do
        ln -s $f .
    done
    [ "${TEGRA_SIGNING_EXCLUDE_TOOLS}" = "1" ] || cp -R ${STAGING_BINDIR_NATIVE}/tegra186-flash/* .
    tegraflash_custom_pre
    mksparse -v --fillpattern=0 "${IMAGE_TEGRAFLASH_ROOTFS}" ${IMAGE_BASENAME}.img
    tegraflash_create_flash_config "${WORKDIR}/tegraflash" ${LNXFILE} ${APPFILE}
    rm -f doflash.sh
    cat > doflash.sh <<END
#!/bin/sh
MACHINE=${MACHINE} ./tegra194-flash-helper.sh flash.xml.in ${DTBFILE} ${MACHINE}.cfg,${MACHINE}-override.cfg ${ODMDATA} ${LNXFILE} "\$@"
END
    chmod +x doflash.sh
    tegraflash_custom_post
    tegraflash_custom_sign_pkg
    rm -f ${IMGDEPLOYDIR}/${IMAGE_NAME}.tegraflash.zip
    zip -r ${IMGDEPLOYDIR}/${IMAGE_NAME}.tegraflash.zip .
    ln -sf ${IMAGE_NAME}.tegraflash.zip ${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.tegraflash.zip
    cd $oldwd
}
create_tegraflash_pkg[vardepsexclude] += "DATETIME"

IMAGE_CMD_tegraflash = "create_tegraflash_pkg"
do_image_tegraflash[depends] += "zip-native:do_populate_sysroot dtc-native:do_populate_sysroot \
                                 ${SOC_FAMILY}-flashtools-native:do_populate_sysroot gptfdisk-native:do_populate_sysroot \
                                 tegra-bootfiles:do_populate_sysroot tegra-bootfiles:do_populate_lic \
                                 virtual/kernel:do_deploy \
                                 ${@'${INITRD_IMAGE}:do_image_complete' if d.getVar('INITRD_IMAGE') != '' else  ''} \
                                 ${@'${IMAGE_UBOOT}:do_deploy ${IMAGE_UBOOT}:do_populate_lic' if d.getVar('IMAGE_UBOOT') != '' else  ''} \
                                 cboot:do_deploy virtual/secure-os:do_deploy ${TEGRA_SIGNING_EXTRA_DEPS}"
IMAGE_TYPEDEP_tegraflash += "${IMAGE_TEGRAFLASH_FS_TYPE}"

oe_make_bup_payload() {
    PATH="${STAGING_BINDIR_NATIVE}/${FLASHTOOLS_DIR}:${PATH}"
    export cbootfilename=${CBOOTFILENAME}
    export tosimgfilename=${TOSIMGFILENAME}
    rm -rf ${WORKDIR}/bup-payload
    mkdir ${WORKDIR}/bup-payload
    oldwd="$PWD"
    cd ${WORKDIR}/bup-payload
    if [ "${SOC_FAMILY}" = "tegra186" ]; then
        dd if=/dev/zero of=badpage.bin bs=4096 count=1
    fi
    # BUP generator really wants to use 'boot.img' for the LNX
    # partition contents
    ln -sf $1 ./boot.img
    # We don't replace APPFILE for BUP payloads
    tegraflash_create_flash_config "${WORKDIR}/bup-payload" boot.img APPFILE bupgen
    ln -sf "${STAGING_DATADIR}/tegraflash/bsp_version" .
    ln -s "${STAGING_DATADIR}/tegraflash/${MACHINE}.cfg" .
    if [ "${SOC_FAMILY}" = "tegra194" ]; then
        ln -s "${STAGING_DATADIR}/tegraflash/${MACHINE}-override.cfg" .
    fi
    for dtb in ${KERNEL_DEVICETREE}; do
	dtbf=`basename $dtb`
        rm -f ./$dtbf
        cp -L "${DEPLOY_DIR_IMAGE}/$dtbf" ./$dtbf
        if [ -n "${KERNEL_ARGS}" ]; then
            fdtput -t s ./$dtbf /chosen bootargs "${KERNEL_ARGS}"
        elif fdtget -t s ./$dtbf /chosen bootargs >/dev/null 2>&1; then
            fdtput -d ./$dtbf /chosen bootargs
        fi
    done
    ln -s "${DEPLOY_DIR_IMAGE}/cboot-${MACHINE}.bin" ./$cbootfilename
    ln -s "${DEPLOY_DIR_IMAGE}/tos-${MACHINE}.img" ./$tosimgfilename
    for f in ${BOOTFILES}; do
        ln -s "${STAGING_DATADIR}/tegraflash/$f" .
    done
    cp ${STAGING_DATADIR}/tegraflash/flashvars .
    . ./flashvars
    if [ "${SOC_FAMILY}" = "tegra186" ]; then
        for var in $FLASHVARS; do
            eval pat=$`echo $var`
            if [ -z "$pat" ]; then
                echo "ERR: missing variable: $var" >&2
                exit 1
            fi
	    fnglob=`echo $pat | sed -e"s,@BPFDTBREV@,\*," -e"s,@BOARDREV@,\*," -e"s,@PMICREV@,\*," -e"s,@CHIPREV@,\*,"`
	    for fname in ${STAGING_DATADIR}/tegraflash/$fnglob; do
                if [ ! -e $fname ]; then
                    bbfatal "$var file(s) not found"
                fi
                ln -sf $fname ./
	    done
	done
    elif [ "${SOC_FAMILY}" = "tegra194" ]; then
        for f in ${STAGING_DATADIR}/tegraflash/tegra19[4x]-*.cfg; do
            ln -sf $f .
	done
	for f in ${STAGING_DATADIR}/tegraflash/tegra194-*-bpmp-*.dtb; do
            ln -sf $f .
	done
    fi
    if [ -n "${NVIDIA_BOARD_CFG}" ]; then
        ln -s "${STAGING_DATADIR}/tegraflash/board_config_${MACHINE}.xml" .
        boardcfg=board_config_${MACHINE}.xml
    else
        boardcfg=
    fi
    export boardcfg
    if [ "${SOC_FAMILY}" != "tegra210" ]; then
        rm -f ./slot_metadata.bin
	cp ${STAGING_DATADIR}/tegraflash/slot_metadata.bin ./
	mkdir ./rollback
	ln -snf ${STAGING_DATADIR}/nv_tegra/rollback/t${@d.getVar('NVIDIA_CHIP')[2:]}x ./rollback/
    fi
    if [ "${TEGRA_SIGNING_EXCLUDE_TOOLS}" != "1" ]; then
	[ "${SOC_FAMILY}" = "tegra210" ] || ln -sf ${STAGING_BINDIR_NATIVE}/tegra186-flash/rollback_parser.py ./rollback/
        ln -sf ${STAGING_BINDIR_NATIVE}/${FLASHTOOLS_DIR}/${SOC_FAMILY}-flash-helper.sh ./
        sed -e 's,^function ,,' ${STAGING_BINDIR_NATIVE}/${FLASHTOOLS_DIR}/l4t_bup_gen.func > ./l4t_bup_gen.func
        ln -sf ${STAGING_BINDIR_NATIVE}/${FLASHTOOLS_DIR}/*.py .
        rm -f ./doflash.sh
        cat <<EOF > ./doflash.sh
export BOARDID=${TEGRA_BOARDID}
export fuselevel=fuselevel_production
export localbootfile=${LNXFILE}
export CHIPREV=${TEGRA_CHIPREV}
EOF
        if [ "${SOC_FAMILY}" = "tegra194" ]; then
            sdramcfg="${MACHINE}.cfg,${MACHINE}-override.cfg"
        else
            sdramcfg="${MACHINE}.cfg"
        fi
	fab="${TEGRA_FAB}"
	boardsku="${TEGRA_BOARDSKU}"
	boardrev="${TEGRA_BOARDREV}"
	for spec__ in ${@' '.join(['"%s"' % entry for entry in d.getVar('TEGRA_BUPGEN_SPECS').split()])}; do
	    eval $spec__
            cat <<EOF >>./doflash.sh
MACHINE=${MACHINE} FAB="$fab" BOARDSKU="$boardsku" BOARDREV="$boardrev" ./${SOC_FAMILY}-flash-helper.sh --bup ./flash.xml.in ${DTBFILE} $sdramcfg ${ODMDATA} "\$@"
EOF
	done
        chmod +x ./doflash.sh
    fi
    tegraflash_custom_sign_bup
    mv ${WORKDIR}/bup-payload/${BUP_PAYLOAD_DIR}/* .
    cd "$oldwd"
}

create_bup_payload_image() {
    local type="$1"
    oe_make_bup_payload ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.${type}
    install -m 0644 ${WORKDIR}/bup-payload/bl_update_payload ${IMGDEPLOYDIR}/${IMAGE_NAME}.bup-payload
    ln -sf ${IMAGE_NAME}.bup-payload ${IMGDEPLOYDIR}/${IMAGE_LINK_NAME}.bup-payload
}
create_bup_payload_image[vardepsexclude] += "DATETIME"

CONVERSIONTYPES += "bup-payload"
CONVERSION_DEPENDS_bup-payload = "${SOC_FAMILY}-flashtools-native coreutils-native tegra-bootfiles tegra-redundant-boot-base nv-tegra-release dtc-native virtual/bootloader:do_deploy virtual/kernel:do_deploy virtual/secure-os:do_deploy ${TEGRA_SIGNING_EXTRA_DEPS}"
CONVERSION_CMD_bup-payload = "create_bup_payload_image ${type}"
IMAGE_TYPES += "cpio.gz.cboot.bup-payload"
