#!/bin/bash

set -euxo pipefail

# This script creates a custom bootable EFI binary by combining an EFI stub,
# Linux kernel, initrd, osrel and cmdline.

# Define variables
STUB=/usr/lib/systemd/boot/efi/linuxx64.efi.stub
KERNEL="${BINARIES_DIR}/bzImage"
INITRD="${BINARIES_DIR}/rootfs-sbnb.cpio"
OS_RELEASE="${TARGET_DIR}/etc/os-release"
# --- MODIFIED KERNEL COMMAND LINE (Read from Buildroot Env) ---
# Read command line from BR2_CMDLINE environment variable provided by Buildroot.
CMDLINE="${BR2_CMDLINE:?Error: BR2_CMDLINE environment variable not set or empty. Check Buildroot kernel configuration (BR2_CMDLINE).}"
# --- END MODIFICATION ---
CMDLINE_TMP=$(mktemp)
OUTPUT=sbnb.efi

# Write the command line to a temporary file
echo -n "${CMDLINE}" > "${CMDLINE_TMP}"

# Calculate alignment
align="$(objdump -p "${STUB}" | awk '{ if ($1 == "SectionAlignment"){print $2} }')"
align=$((16#$align))

# Calculate offsets for sections
stub_line=$(objdump -h "${STUB}" | tail -2 | head -1)
stub_size=0x$(echo "$stub_line" | awk '{print $3}')
stub_offs=0x$(echo "$stub_line" | awk '{print $4}')
osrel_offs=$((stub_size + stub_offs))
osrel_offs=$((osrel_offs + align - osrel_offs % align))
cmdline_offs=$((osrel_offs + $(stat -Lc%s "${OS_RELEASE}")))
cmdline_offs=$((cmdline_offs + align - cmdline_offs % align))
splash_offs=$((cmdline_offs + $(stat -Lc%s "${CMDLINE_TMP}")))
splash_offs=$((splash_offs + align - splash_offs % align))
linux_offs=$((splash_offs))
initrd_offs=$((linux_offs + $(stat -Lc%s "${KERNEL}")))
initrd_offs=$((initrd_offs + align - initrd_offs % align))

# Use objcopy to add sections to the EFI stub
objcopy \
    --add-section .osrel="${OS_RELEASE}" --change-section-vma .osrel=$(printf 0x%x $osrel_offs) \
    --add-section .cmdline="${CMDLINE_TMP}" --change-section-vma .cmdline=$(printf 0x%x $cmdline_offs) \
    --add-section .linux="${KERNEL}" --change-section-vma .linux=$(printf 0x%x $linux_offs) \
    --add-section .initrd="${INITRD}" --change-section-vma .initrd=$(printf 0x%x $initrd_offs) \
    "${STUB}" "${OUTPUT}"

# Clean up temporary file
rm -f "${CMDLINE_TMP}"

# Output the result
echo "Output: ${OUTPUT}"

# Move the final EFI file to the standard Buildroot images directory (BINARIES_DIR=output/images)
mv "${OUTPUT}" "${BINARIES_DIR}/"
echo "Moved ${OUTPUT} to ${BINARIES_DIR}/"
