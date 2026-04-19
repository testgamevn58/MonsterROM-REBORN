if [[ "$SOURCE_PLATFORM_SDK_VERSION" -lt 37 ]]; then
    LOG_STEP_IN "- Replacing btapex from S24+"
    ADD_TO_WORK_DIR "e2sxxx" "system" "system/apex/com.android.bt.apex" 0 0 644 
    LOG_STEP_OUT
    
    [ -f "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" ] && rm -f "$WORK_DIR/system/system/lib64/libbluetooth_jni.so"
fi

if [ ! -f "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" ]; then
    LOG_STEP_IN "- Extracting libbluetooth_jni.so from com.android.bt.apex"

    if [ -d "$TMP_DIR" ]; then
        EVAL "rm -rf \"$TMP_DIR\""
    fi
    mkdir -p "$TMP_DIR"

    EVAL "unzip -j \"$WORK_DIR/system/system/apex/com.android.bt.apex\" \"apex_payload.img\" -d \"$TMP_DIR\""

    if ! sudo -n -v &> /dev/null; then
        LOG "\033[0;33m! Asking user for sudo password\033[0m"
        if ! sudo -v 2> /dev/null; then
            ABORT "Root permissions are required to unpack APEX image"
        fi
    fi

    mkdir -p "$TMP_DIR/tmp_out"
    EVAL "sudo mount -o ro \"$TMP_DIR/apex_payload.img\" \"$TMP_DIR/tmp_out\""
    EVAL "sudo cat \"$TMP_DIR/tmp_out/lib64/libbluetooth_jni.so\" > \"$WORK_DIR/system/system/lib64/libbluetooth_jni.so\""

    EVAL "sudo umount \"$TMP_DIR/tmp_out\""
    rm -rf "$TMP_DIR"

    SET_METADATA "system" "system/lib64/libbluetooth_jni.so" 0 0 644 "u:object_r:system_lib_file:s0"

    LOG_STEP_OUT
fi

LOG_STEP_IN "- Disabling VaultKeeper/FaultKeeper support"
if [[ "$SOURCE_PLATFORM_SDK_VERSION" -lt 37 ]]; then
    # S24+ Patching Logic (SDK < 37)
    if xxd -p -c 0 "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" | grep -q "39d9199428518152"; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" "39d9199428518152" "000080d228518152"
    elif xxd -p -c 0 "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" | grep -q "2897773948050037"; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" "2897773948050037" "289777392a000014"
    elif xxd -p -c 0 "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" | grep -q "183a009048050037"; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" "183a009048050037" "183a00902a000014"
    else
        ABORT "No known patch available for the supplied S24 libbluetooth_jni.so"
    fi
else
    if xxd -p -c 0 "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" | grep -q "5661756c744b6565706572"; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" "5661756c744b6565706572" "289777392a000014"
    elif xxd -p -c 0 "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" | grep -q "4661756c744b6565706572"; then
        HEX_PATCH "$WORK_DIR/system/system/lib64/libbluetooth_jni.so" "4661756c744b6565706572" "183a00902a000014"
    else
        ABORT "No known patch available for the supplied standard libbluetooth_jni.so"
    fi
fi
LOG_STEP_OUT