#!/usr/bin/env bash
# Copyright (c) 2025 Salvo Giangreco
# SPDX-License-Identifier: GPL-3.0-or-later

source "$SRC_DIR/scripts/utils/build_utils.sh" || exit 1

FORCE=false
FS_TYPE=""
SPARSE=false
MAP_FILE=false
INPUT_DIR=""
PARTITION=""
IMAGE_SIZE=""
INODES=""
MOUNT_POINT=""
OUTPUT_FILE=""
FILE_CONTEXT_FILE=""
FS_CONFIG_FILE=""

BUILD_IMAGE_MKFS()
{
    local SPARSE=$SPARSE
    local MANUAL_SPARSE=false

    if $SPARSE && [[ "$(awk '/MemTotal/ { print int ($2 / 1024) }' "/proc/meminfo")" -lt "10240" ]]; then
        SPARSE=false
        MANUAL_SPARSE=true
    fi

    local BUILD_CMD

    case "$FS_TYPE" in
        "ext4")
            BUILD_CMD+="mkuserimg_mke2fs "
            if $SPARSE; then
                BUILD_CMD+="-s "
            fi
            BUILD_CMD+="\"$INPUT_DIR\" \"$OUTPUT_FILE\" \"ext4\" \"$MOUNT_POINT\" "
            BUILD_CMD+="\"$IMAGE_SIZE\" -j \"0\" -T \"1230735600\" -C \"$FS_CONFIG_FILE\" "
            if $MAP_FILE; then
                BUILD_CMD+="-B \"${OUTPUT_FILE//.img/.map}\" "
            fi
            BUILD_CMD+="-L \"$MOUNT_POINT\" "
            if [ "$INODES" ]; then
                BUILD_CMD+="-i \"$INODES\" "
            fi
            BUILD_CMD+="-M \"0\" --inode_size \"256\" \"$FILE_CONTEXT_FILE\""

            if ! grep -q -F "lost+found" "$FILE_CONTEXT_FILE"; then
                if [[ "$PARTITION" == "system" ]]; then
                    echo "/lost\+found u:object_r:rootfs:s0" >> "$FILE_CONTEXT_FILE"
                else
                    echo "/$PARTITION/lost\+found $(head -n 1 "$FILE_CONTEXT_FILE" | cut -f 2 -d " ")" >> "$FILE_CONTEXT_FILE"
                fi
            fi

            if ! grep -q -F "lost+found" "$FS_CONFIG_FILE"; then
                if [[ "$PARTITION" == "system" ]]; then
                    echo "lost+found 0 0 700 capabilities=0x0" >> "$FS_CONFIG_FILE"
                else
                    echo "$PARTITION/lost+found 0 0 700 capabilities=0x0" >> "$FS_CONFIG_FILE"
                fi
            fi
            ;;
        "erofs")
            BUILD_CMD+="mkfs.erofs -z \"lz4hc,9\" -b \"4096\" --mount-point \"$MOUNT_POINT\" "
            BUILD_CMD+="--fs-config-file \"$FS_CONFIG_FILE\" --file-contexts \"$FILE_CONTEXT_FILE\" -T \"1640995200\" "
            if $MAP_FILE; then
                BUILD_CMD+="--block-list-file \"${OUTPUT_FILE//.img/.map}\" "
            fi
            BUILD_CMD+="\"$OUTPUT_FILE\" \"$INPUT_DIR\""

            if $SPARSE; then
                MANUAL_SPARSE=true
            fi
            ;;
        "f2fs")
            BUILD_CMD+="mkf2fsuserimg \"$OUTPUT_FILE\" \"$IMAGE_SIZE\" "
            if $SPARSE; then
                BUILD_CMD+="-S "
            fi
            BUILD_CMD+="-C \"$FS_CONFIG_FILE\" -f \"$INPUT_DIR\" -s \"$FILE_CONTEXT_FILE\" -t \"$MOUNT_POINT\" -T \"1640995200\" "
            if $MAP_FILE; then
                BUILD_CMD+="-B \"${OUTPUT_FILE//.img/.map}\" "
            fi
            BUILD_CMD+="-L \"$MOUNT_POINT\" --readonly -b \"4096\""

            if [[ "$PARTITION" != "system" ]] && ! grep -q "^/$PARTITION/$PARTITION " "$FILE_CONTEXT_FILE"; then
                echo "/$PARTITION/$PARTITION $(head -n 1 "$FILE_CONTEXT_FILE" | cut -d " " -f 2)" >> "$FILE_CONTEXT_FILE"
            fi
            ;;
    esac

    EVAL "$BUILD_CMD" || exit 1

    if $MANUAL_SPARSE; then
        EVAL "img2simg \"$OUTPUT_FILE\" \"$OUTPUT_FILE.sparse\"" || exit 1
        mv -f "$OUTPUT_FILE.sparse" "$OUTPUT_FILE"
    fi
}

CALCULATE_SIZE_AND_RESERVED()
{
    local SIZE="$1"
    if [[ "$FS_TYPE" == "erofs" ]]; then
        SIZE="$(bc -l <<< "scale=0; ($SIZE * 1.1) / 1")"
        SIZE="$(bc -l <<< "$SIZE + 16777216")"
    fi
    echo "$SIZE"
}

GET_INODE_USAGE()
{
    local INODES
    local SPARE_INODES

    INODES="$(find "$1" -print | wc -l)"
    SPARE_INODES="$(bc -l <<< "scale=0; ($INODES * 6) / 100")"
    [[ "$SPARE_INODES" -lt "12" ]] && SPARE_INODES="12"

    bc -l <<< "$INODES + $SPARE_INODES"
}

PREPARE_SCRIPT()
{
    if [[ "$#" == 0 ]]; then
        PRINT_USAGE
        exit 1
    fi

    FS_TYPE="$1"
    if [[ "$FS_TYPE" != "ext4" ]] && [[ "$FS_TYPE" != "f2fs" ]] && [[ "$FS_TYPE" != "erofs" ]]; then
        LOGE "Unsupported file system type: $FS_TYPE"
        exit 1
    fi

    shift
    while [[ "$1" == "-"* ]]; do
        if [[ "$1" == "--avb" ]] || [[ "$1" == "--no-avb" ]]; then
            shift; continue
        elif [[ "$1" == "--force" ]] || [[ "$1" == "-f" ]]; then
            FORCE=true
        elif [[ "$1" == "--generate-map" ]] || [[ "$1" == "-m" ]]; then
            MAP_FILE=true
        elif [[ "$1" == "--inodes" ]] || [[ "$1" == "-i" ]]; then
            shift; INODES="$1"
        elif [[ "$1" == "--output" ]] || [[ "$1" == "-o" ]]; then
            shift; OUTPUT_FILE="$1"
        elif [[ "$1" == "--partition-name" ]] || [[ "$1" == "-p" ]]; then
            shift; PARTITION="$1"
        elif [[ "$1" == "--partition-size" ]] || [[ "$1" == "-s" ]]; then
            shift; IMAGE_SIZE="$1"
        elif [[ "$1" == "--sparse" ]] || [[ "$1" == "-S" ]]; then
            SPARSE=true
        else
            LOGE "Unknown option: $1"
            exit 1
        fi
        shift
    done

    INPUT_DIR="$1"
    if [ ! "$INPUT_DIR" ]; then
        PRINT_USAGE
        exit 1
    elif [ ! -d "$INPUT_DIR" ]; then
        LOGE "Folder not found: ${INPUT_DIR//$SRC_DIR\//}"
        exit 1
    fi

    shift

    if [ ! "$PARTITION" ]; then
        PARTITION="$(basename "$INPUT_DIR")"
        if ! IS_VALID_PARTITION_NAME "$PARTITION"; then
            LOGE "\"$PARTITION\" is not a valid partition name."
            exit 1
        fi
    fi

    MOUNT_POINT="$PARTITION"
    [[ "$PARTITION" == "system" ]] && MOUNT_POINT="/"

    if [ ! "$OUTPUT_FILE" ]; then
        OUTPUT_FILE="$(dirname "$INPUT_DIR")/$PARTITION.img"
    fi

    if [ -f "$OUTPUT_FILE" ]; then
        if $FORCE; then
            rm -rf "$OUTPUT_FILE"
        else
            LOGE "Output file already exists."
            exit 1
        fi
    fi

    FILE_CONTEXT_FILE="$1"
    shift
    FS_CONFIG_FILE="$1"
}

PRINT_USAGE()
{
    echo "Usage: build_fs_image <fs> [options] <dir> <file_context> <fs_config>" >&2
    echo " -f, --force : Force delete output file" >&2
    echo " -i, --inodes : (ext4 only) Specify the extfs inodes count" >&2
    echo " -m, --generate-map : Generates block map file" >&2
    echo " -o, --output : Specify the output image path" >&2
    echo " -p, --partition-name : Specify the partition name" >&2
    echo " -s, --partition-size : Specify the partition size" >&2
    echo " -S, --sparse : Outputs an Android sparse image" >&2
}

ROUND_UP_TO_4K()
{
    local ROUNDED
    ROUNDED="$(bc -l <<< "$1 + 4095")"
    ROUNDED="$(bc -l <<< "scale=0; $ROUNDED - ($ROUNDED % 4096)")"
    echo "$ROUNDED"
}

PREPARE_SCRIPT "$@"

if $SPARSE; then
    LOG_STEP_IN "- Starting build_fs_image for $(basename "$OUTPUT_FILE") ($FS_TYPE+sparse)..."
else
    LOG_STEP_IN "- Starting build_fs_image for $(basename "$OUTPUT_FILE") ($FS_TYPE)..."
fi

if [ ! "$IMAGE_SIZE" ]; then
    LOG_STEP_IN "! Partition size is not set, detecting minimum size"

    if [[ "$FS_TYPE" == "erofs" ]]; then
        BUILD_IMAGE_MKFS
        IMAGE_SIZE="$(GET_IMAGE_SIZE "$OUTPUT_FILE")"
    else
        IMAGE_SIZE="$(GET_DISK_USAGE "$INPUT_DIR")"
    fi

    LOG "- The tree size of $(basename "$OUTPUT_FILE") is $IMAGE_SIZE bytes ($(bc -l <<< "scale=0; $IMAGE_SIZE / 1048576") MB)"

    IMAGE_SIZE="$(CALCULATE_SIZE_AND_RESERVED "$IMAGE_SIZE")"
    IMAGE_SIZE="$(ROUND_UP_TO_4K "$IMAGE_SIZE")"

    if [[ "$FS_TYPE" == "ext4" ]]; then
        if [ ! "$INODES" ]; then
            INODES="$(GET_INODE_USAGE "$INPUT_DIR")"
        fi
        SPARSE=false BUILD_IMAGE_MKFS
        IMAGE_INFO="$(tune2fs -l "$OUTPUT_FILE")"
        rm -f "$OUTPUT_FILE"

        FREE_SIZE="$(grep -w "Free blocks" <<< "$IMAGE_INFO" | tr -d " " | cut -d ":" -f 2)"
        FREE_SIZE="$(bc -l <<< "$FREE_SIZE * 4096")"
        IMAGE_SIZE="$(bc -l <<< "$IMAGE_SIZE - $FREE_SIZE")"
        IMAGE_SIZE="$(bc -l <<< "scale=0; ($IMAGE_SIZE * 1003) / 1000")"
        [[ "$IMAGE_SIZE" -lt "262144" ]] && IMAGE_SIZE="262144"
        IMAGE_SIZE="$(ROUND_UP_TO_4K "$IMAGE_SIZE")"
        INODES="$(grep -w "Inode count" <<< "$IMAGE_INFO" | tr -d " " | cut -d ":" -f 2)"
        FREE_INODES="$(grep -w "Free inodes" <<< "$IMAGE_INFO"| tr -d " " | cut -d ":" -f 2)"
        INODES="$(bc -l <<< "$INODES - $FREE_INODES")"
        SPARE_INODES=$(bc -l <<< "scale=0; ($INODES * 2) / 100")
        [[ "$SPARE_INODES" -lt 1 ]] && SPARE_INODES=1
        INODES="$(bc -l <<< "$INODES + $SPARE_INODES")"
    elif [[ "$FS_TYPE" == "f2fs" ]]; then
        [[ "$IMAGE_SIZE" -lt "23068672" ]] && IMAGE_SIZE="23068672"
        SPARSE=false BUILD_IMAGE_MKFS
        IMAGE_INFO="$(fsck.f2fs -l "$OUTPUT_FILE")"
        rm -f "$OUTPUT_FILE"
        BLOCK_COUNT="$(grep -w "block_count" <<< "$IMAGE_INFO" | tr -d " " | cut -d ":" -f 2)"
        LOG_BLOCKSIZE="$(grep -w "log_blocksize" <<< "$IMAGE_INFO" | tr -d " " | cut -d ":" -f 2)"
        IMAGE_SIZE="$((BLOCK_COUNT << LOG_BLOCKSIZE))"
    fi

    LOG "- Allocating $IMAGE_SIZE bytes ($(bc -l <<< "scale=0; $IMAGE_SIZE / 1048576") MB) for $(basename "$OUTPUT_FILE")"
    LOG_STEP_OUT
fi

LOG "- Building image"
if [ ! -f "$OUTPUT_FILE" ]; then
    BUILD_IMAGE_MKFS
fi

LOG_STEP_OUT
exit 0
