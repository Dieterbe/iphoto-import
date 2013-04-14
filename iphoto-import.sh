#!/bin/bash
# TODO: make faster

source /usr/lib/libui.sh
source "$(dirname "$0")"/config.sh
path_prefix="$iphoto_out/$(basename "$iphoto_in")_"
echo "cleaning old incompleted dirs.. ('${path_prefix}*.auto_generated.new')"
if egrep -q "[[:space:]]" <<< "$path_prefix"; then
    die_error "whitespace in path prefix: $path_prefix"
fi

rm -rvf "${path_prefix}"*.auto_generated.new
echo "processing files in $iphoto_in (symlinking to $path_prefix<device>.auto_generated.new if it's new)"
while read file; do
    set -o pipefail # normally i would just use $PIPESTATUS but that seems to not work in a subshell
    # unfortunately, the output of the exiv2 command can contain bogus (trailing) whitespace..
    device=$(exiv2 -g Exif.Image.Model -P v "$file" | sed -e 's/^[ \t]*//' -e 's/[ \t]*$//' -e 's# #_#g')
    ret=$?
    # it exit(253)'s on success. wtf.
    if [ $ret -gt 0 -a $ret -ne 253 ]; then
        echo "skipping '$file', because exiv2 couldn't get the model from it"
        continue
    fi
    if [ -z "$device" ]; then
        device='unknown'
    fi
    dir="$path_prefix${device}.auto_generated.new"
    mkdir -p "$dir" || die_error "Can't mkdir -p '$dir'"
    cd "$dir" || die_error "Can't cd '$dir'"
    base="$(basename "$file")"
    if [ -e "$base" ]; then
        if ! diff -q "$base" "$file" >/dev/null; then
            # for some pairs of known files, we ignore this. on manual inspection they look the same. maybe a bit error or something...
            md5sum=$(md5sum "$base" "$file" | cut -d' ' -f1 | sort | md5sum | cut -d' ' -f1)
            if [ $md5sum == 7d253cbdb83e9532c3be858481104614 ]; then
                true
            else
                die_error "'$dir/$(basename "$file")' already exists and is different, can't symlink to '$file'"
            fi
        fi
        # if files don't differ, this is just one of the (sometimes many) dupes within the iphoto library. so no action needed.
    else
        ln -s "$file" .
    fi
    cd - > /dev/null || die_error "Can't cd back after going into '$dir'"
done < <(find "$iphoto_in" -type f | grep -v AppleDouble)
echo "finishing up new directories.."
cd "$iphoto_out" || die_error "Can't cd '$iphoto_out'"
for dir_old in *.auto_generated.new; do
    dir_new="${dir_old/.auto_generated.new}"
    rm -rfv "$dir_new" || die_error "Can't rm '$dir_new'"
    mv -v "$dir_old" "$dir_new" || die_error "Can't mv '$dir_old' '$dir_new'"
    echo "generated by $@ on $(date)" > $dir_new/.auto-generated || die_error "Can't put .auto-generated notice in $dir_new"
done
echo "done"
