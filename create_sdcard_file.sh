#!/bin/bash

SUPPORTED_PARTITION_TABLE="GPT | DOS"
SFDISK_SCRIPT_NAME="sfdisk/partition.sfdisk"	#TODO change it to a temporary file with a keep option and a clean trap
SDCARD_FILENAME="raw.sdcard"			#TODO handle sdcard filename input ($2)

#TODO add sfdisk temp folder creation

declare -a PARTITION_NAME
declare -a PARTITION_START
declare -a PARTITION_SIZE
declare -a PARTITION_TYPE
declare -a PARTITION_FILENAME
declare -a PARTITION_BOOTABLE

declare PARTITION_TABLE_TYPE
declare SDCARD_FILE_SIZE
declare FIRST_SECTOR
declare TOTAL_OF_PARTITION

function parse_layout () {
	
	local i=0

	while IFS=$'\t' read -r a b c d partName
	do
		case $i in
		0)
			echo "Loading sdcard configuration ...";;
		1)
			PARTITION_TABLE_TYPE=$a
			SDCARD_FILE_SIZE=$b
			FIRST_SECTOR=$c
			TOTAL_OF_PARTITION=$d
			echo -e "Configuration found :\n type=$a\n size=$b\n first-lba=$c\n partNumber=$d";;
		2)
			echo "";;
		*)
			PARTITION_NAME+=(${a})
			PARTITION_START+=($b)
			PARTITION_SIZE+=($c)
			PARTITION_TYPE+=($d)
			PARTITION_FILENAME+=($partName);;
		esac

		i=$((i+1))

	done < $1

}

function create_void_sdcard_file () {
	
	#TODO add force option
	if [ -f "${SDCARD_FILENAME}" ]; then
		rm -rf ${SDCARD_FILENAME}
	fi

	echo "Create Raw empty image: ${SDCARD_FILENAME} of ${SDCARD_FILE_SIZE}MB"
	echo " dd if=/dev/zero of=${SDCARD_FILENAME} bs=1024 count=0 seek=${SDCARD_FILE_SIZE}K"

	dd if=/dev/zero of=${SDCARD_FILENAME} bs=1024 count=0 seek=${SDCARD_FILE_SIZE}K
}

function add_gpt_partition () {

	for ((i=0;i<TOTAL_OF_PARTITION;i++))
	do
		case ${PARTITION_TYPE[${i}],,} in
			binary)
				echo -e "start=\t${PARTITION_START[${i}]}, size=\t${PARTITION_SIZE[${i}]}, type=8DA63339-0007-60C0-C436-083AC8230908, name=\"${PARTITION_NAME[${i}]}\"" >> sfdisk/partition.sfdisk;;
			system)
				echo -e "start=\t${PARTITION_START[${i}]}, size=\t${PARTITION_SIZE[${i}]}, type=BC13C2FF-59E6-4262-A352-B275FD6F7172, attrs=LegacyBIOSBootable, name=\"${PARTITION_NAME[${i}]}\", bootable," >> sfdisk/partition.sfdisk;;
			filesystem)
				echo -e "start=\t${PARTITION_START[${i}]}, size=\t${PARTITION_SIZE[${i}]}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"${PARTITION_NAME[${i}]}\"" >> sfdisk/partition.sfdisk;;
			*)
				echo "Error : Unknow partition type ${PARTITION_TYPE[${i}]}"
				exit 3;;
		esac
	done

}

function add_dos_partition () {
	echo "Error : ${PARTITION_TABLE_TYPE} partition not supported yet" #TODO add dos partition support
	exit 2
}

function create_partition_table () {


	#write sfdisk partition file header 
	echo -e "label:${PARTITION_TABLE_TYPE}\nfirst-lba:${FIRST_SECTOR}\n" > sfdisk/partition.sfdisk

	case ${PARTITION_TABLE_TYPE} in
		gpt)
			add_gpt_partition;;
		dos)
			add_dos_partition;;
		*)
			echo "Error : ${PARTITION_TABLE_TYPE} partition not supported yet (or maybe mispelled, supported types are : ${SUPPORTED_PARTITION_TABLE})"
			exit 2;;
	esac

	#Write the partition table using sfdisk
	sfdisk ${SDCARD_FILENAME} < ${SFDISK_SCRIPT_NAME}

	if [ $? -ne 0 ] ; then
		echo "Error : It seems that something went wrong with sfdisk, check the sfdisk output to find more"
		exit 1
	fi
}

function populate_partition_table () {
	
	for ((i=0;i<TOTAL_OF_PARTITION;i++))
	do
		echo "Populating partition ${PARTITION_NAME[${i}]} with ${$PARTITION_FILENAME$[${i}]} ..."
		echo " dd if=${PARTITION_FILENAME$[${i}]} of=${SDCARD_FILENAME} conv=fdatasync,notrunc seek=1 bs=$((512*${PARTITION_START[${i}]}))"
		#dd if=${PARTITION_FILENAME$[${i}]} of=${SDCARD_FILENAME} conv=fdatasync,notrunc seek=1 bs=$((512*${PARTITION_START[${i}]}))
	done
}

parse_layout $1 #TODO put $1 to variable ... maybe with the option parser

create_void_sdcard_file
create_partition_table
populate_partition_table

#		echo "PARTITION_NAME = ${PARTITION_NAME[${i}]}; PARTITION_START = ${PARTITION_START[${i}]}; PARTITION_SIZE = ${PARTITION_SIZE[${i}]}; PARTITION_TYPE = ${PARTITION_TYPE[${i}]}; PARTITION_FILENAME = ${PARTITION_FILENAME[${i}]}"

exit 0
