#!/bin/bash

# Keep working files generated during processing
keepFiles=false
# Replace files in place
moveFiles=false

while true
do
    case "$1" in
        --keep-files)
            echo "Option enabled to keep working files"
            keepFiles=true
            shift;;
        --move)
            echo "Option enabled to move files to /Volumes/Video/Movies"
            moveFiles=true
            shift;;
        "")
            break;;
        *)
            targetDir=$1
            shift;;
    esac
done

if [[ ! -d $targetDir ]]
then
    echo "Directory not found: '$targetDir'"
    exit 1
fi

echo "Processing directory: '$targetDir'"

# Get the script's directory path; do this before pushing the targetDir
scriptDir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)

pushd "$targetDir" > /dev/null

# Get the subdirectory paths
toolsPath=$scriptDir/tools
configPath=$scriptDir/config

# Reference the dovi_tool, mkvextract, and mkvmerge executables and the JSON file in their respective subdirectories
doviToolPath=/opt/homebrew/bin/dovi_tool
mkvextractPath=/Applications/MKVToolNix.app/Contents/MacOS/mkvextract
mkvmergePath=/Applications/MKVToolNix.app/Contents/MacOS/mkvmerge
mediaInfoPath=/opt/homebrew/bin/mediainfo
jsonFilePath=$configPath/DV7toDV8.json

for mkvFile in "$targetDir"/*.mkv
do
    mkvBase=$(basename "$mkvFile" .mkv)
    BL_EL_RPU_HEVC=$mkvBase.BL_EL_RPU.hevc
    DV7_EL_RPU_HEVC=$mkvBase.DV7.EL_RPU.hevc
    DV8_BL_RPU_HEVC=$mkvBase.DV8.BL_RPU.hevc
    DV8_RPU_BIN=$mkvBase.DV8.RPU.bin

    printf "\nProcessing file: '$mkvBase.mkv'...\n"

    # only work on files containing Profile 7 DV
    printf "  Checking file for Dolby Vision Profile 7..."
    PROFILE_CHECK=$("$mediaInfoPath" "$mkvFile" | grep "Profile 7")

    if [[ $PROFILE_CHECK == "" ]]
    then
        printf "skipping."
        continue
    else
        printf "found, processing\n"
    fi

    echo "  Demuxing BL+EL+RPU HEVC from MKV..."
    "$mkvextractPath" "$mkvFile" tracks 0:"$BL_EL_RPU_HEVC"

    if [[ $? != 0 ]] || [[ ! -f "$BL_EL_RPU_HEVC" ]]
    then
        echo "    Failed to extract HEVC track from MKV. Quitting."
        # ROB EDIT just go to next file
        # exit 1
        continue
    fi

    echo "  Demuxing DV7 EL+RPU HEVC for you to archive for future use..."
    "$doviToolPath" demux --el-only "$BL_EL_RPU_HEVC" -e "$DV7_EL_RPU_HEVC"

    if [[ $? != 0 ]] || [[ ! -f "$DV7_EL_RPU_HEVC" ]]
    then
        echo "    Failed to demux EL+RPU HEVC file. Quitting."
        exit 1
    fi

    # If the EL is less than ~10MB, then the input was likely DV8 rather than DV7
    # Extract and plot the RPU for archiving purposes, as it may be CMv4.0
    if [[ $(wc -c < "$DV7_EL_RPU_HEVC") -lt 10000000 ]]
    then
        echo "  Extracting original RPU for you to archive for future use..."
        "$doviToolPath" extract-rpu "$BL_EL_RPU_HEVC" -o "$mkvBase.RPU.bin"
        "$doviToolPath" plot "$mkvBase.RPU.bin" -o "$mkvBase.L1_plot.png"
    fi

    echo "  Converting BL+EL+RPU to DV8 BL+RPU..."
    "$doviToolPath" --edit-config "$jsonFilePath" convert --discard "$BL_EL_RPU_HEVC" -o "$DV8_BL_RPU_HEVC"

    if [[ $? != 0 ]] || [[ ! -f "$DV8_BL_RPU_HEVC" ]]
    then
        echo "    File to convert BL+RPU. Quitting."
        exit 1
    fi

    echo "  Deleting BL+EL+RPU HEVC..."
    if [[ $keepFiles == false ]]
    then
        rm "$BL_EL_RPU_HEVC"
    fi

    echo "  Extracting DV8 RPU..."
    "$doviToolPath" extract-rpu "$DV8_BL_RPU_HEVC" -o "$DV8_RPU_BIN"

    echo "  Plotting L1..."
    "$doviToolPath" plot "$DV8_RPU_BIN" -o "$mkvBase.DV8.L1_plot.png"

    echo "  Remuxing DV8 MKV..."
    "$mkvmergePath" -o "$mkvBase.DV8.mkv" -D "$mkvFile" "$DV8_BL_RPU_HEVC" --track-order 1:0

    if [[ $keepFiles == false ]]
    then
        echo "  Cleaning up..."
        rm "$DV8_RPU_BIN"
        rm "$DV8_BL_RPU_HEVC"
    fi


    # Moves files from wherever they were processed to /Volumes/Video/Movies
    # Run this version in the future when we rip movies with MakeMKV so that
    # we process them before moving them to Movies
    if [[ $moveFiles ]]
    then
        echo "  Moving EL to /Volumes/Video/DV7 Enhancement Layers..."
        pv < "$mkvBase.DV8.L1_plot.png" > "/Volumes/Video/DV7 Enhancement Layers/$mkvBase.DV8.L1_plot.png"
        rm "$mkvBase.DV8.L1_plot.png"
        pv < "$DV7_EL_RPU_HEVC" > "/Volumes/Video/DV7 Enhancement Layers/$DV7_EL_RPU_HEVC"
        rm "$DV7_EL_RPU_HEVC"
        echo "  Replacing original MKV..."
        pv < "$mkvBase.DV8.mkv" > "/Volumes/Video/Movies/$mkvBase.mkv"
        rm "$mkvBase.DV8.mkv"
    else
        # Replaces files assuming we processed them directly in /Volumes/Video/Movies
        # Run this version to convert the existing Movies directory completely
        echo "  Moving EL to /Volumes/Video/DV7 Enhancement Layers..."
        mv "$mkvBase.DV8.L1_plot.png" "../DV7 Enhancement Layers"
        mv "$DV7_EL_RPU_HEVC" "../DV7 Enhancement Layers"
        echo "  Replacing original MKV..."
        mv "$mkvBase.mkv" "$mkvBase.mkv.bak"
        mv "$mkvBase.DV8.mkv" "$mkvBase.mkv"
        rm "$mkvBase".mkv.bak
    fi

    echo "  Done with ${mkvBase}.mkv"
done

popd > /dev/null
echo "Done with directory."

# In the future, to reverse these steps: https://github.com/nekno/DV7toDV8/discussions/11
