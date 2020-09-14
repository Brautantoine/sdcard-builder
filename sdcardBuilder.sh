#!/bin/bash

SUPPORTED_PARTITION_TABLE="GPT | DOS"
TEMP_DIR=".sfdisk"
SFDISK_SCRIPT_NAME="${TEMP_DIR}/partition.sfdisk"
SDCARD_FILENAME="raw.sdcard"



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

trap "clean_env 5" 2


function clean_env () {
	rm -rf ${TEMP_DIR}

	exit $1
}

function set_env () {
	mkdir ${TEMP_DIR}
}

function display_help () {

	echo "Usage : $0 <sdcard layout.tsv> [options]

Option :

	-h | --help		Dislpay this message and quit
	-v | --version		Display script version and quit
	-s | --source	<path>	indicate root source folder	
	-p | --only-parse	Parse the tsv then quit"

}

function display_version () {

	echo "$0 version 2.0"

}

function parse_option () {

LAYOUT_FILE=$1

if ! grep -q -i "^.*\.tsv$" <<< ${LAYOUT_FILE} ; then
	echo "Error : first argument not a valid .tsv file"
	display_help
	clean_env 6
fi

while getopts ":hsvp-:*:" opt ; do
	case $opt in
		h )
			display_help
			clean_env 0 ;;
		v )
			display_version
			clean_env 0 ;;
		p )
			ONLY_PARSE="true";;
		s )
			shift 1
			SOURCE=${opt}
			echo ${SOURCE}
			clean_env 7;;
		- ) case $OPTARG in
			help )
				display_help
				clean_env 0 ;;
			version )
				display_version
				clean_env 0;;
			only-parse )
				ONLY_PARSE="true";;
			source )
				shift 1
				SOURCE=${OPTARG};;
			* )
				echo "Unrecognized option : --$OPTARG"
				display_help
				clean_env 1 ;;
			esac ;;
		* )
			echo Unrecognized option : $opt
			display_help
			clean_env 1 ;;
	esac
done
shift $(($OPTIND-1))

}

function parse_layout () {
	
	local i=0

	while IFS=$'\t' read -r a b c d partName other
	do
		case $i in
		0)
			echo "Loading sdcard configuration ...";;
		1)
			PARTITION_TABLE_TYPE=$a
			SDCARD_FILE_SIZE=$b
			FIRST_SECTOR=$c
			TOTAL_OF_PARTITION=$d
			SDCARD_FILENAME=$partName
			echo -e "Configuration found :\n type=$a\n size=$b\n first-lba=$c\n partNumber=$d";;
		2)
			echo "";;
		3)
			echo "";;
		*) # TODO force eval
			PARTITION_NAME+=(${a})
			PARTITION_START+=($b)
			PARTITION_SIZE+=($c)
			PARTITION_TYPE+=($d)

			if [ -z $(eval "echo ${partName}") ] ; then
			echo "ERROR empty partition file name for ${PARTITION_NAME}"
				if [[ ${partName} =~ "\${?[^}]*}?" ]] ; then
					echo "${partName} is not defined in the environement"
				else
					echo "Partition file name is empty"
				fi
				clean_env 8
			fi

			if [ -f ${partName} ] ; then
				echo "ERROR cannot find ${partName}"
			fi

			eval PARTITION_FILENAME+=(${partName});;
			#PARTITION_FILENAME+=($(eval "echo ${partName}"))
#			echo "interpoled : ${PARTITION_FILENAME}";;
		esac

		i=$((i+1))

	done < $1

	# TODO recalculate size

}

function validate_layout () {

	if [ -f "${SOURCE}" ] ; then
		SOURCE="${SOURCE}/"
	fi

	for ((i=0;i<TOTAL_OF_PARTITION;i++))
	do
		if [ $((${PARTITION_SIZE[${i}]}*512)) -lt $(sed -e 's/[^[:digit:]]//g' <<< $(du ${SOURCE}${PARTITION_FILENAME[${i}]})) ] ; then
			echo "ERROR : Partition size : ${PARTITION_SIZE[${i}]} sectors (i.e $((${PARTITION_SIZE[${i}]}*512)) bytes ) seems inferior to partition file size : $(echo $( du  ${SOURCE}${PARTITION_FILENAME[${i}]} ) | sed -e 's/ .*$//') bytes "
			clean_env 9
		fi
	done

}

function recalculate_partition_size () {

	for ((i=0;i<TOTAL_OF_PARTITION;i++))
	do
		case ${PARTITION_SIZE[${i}],,} in

			auto)
echo 'not supported yet';;
				#TODO calculate minimal size
			fill)
echo 'not supported yet';;
				#TODO calculate max size
			*)
echo 'not supported yet';;
				#TODO check if it's not an illegal size
		esac
	done

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
				echo -e "start=\t${PARTITION_START[${i}]}, size=\t${PARTITION_SIZE[${i}]}, type=8DA63339-0007-60C0-C436-083AC8230908, name=\"${PARTITION_NAME[${i}]}\"" >> ${SFDISK_SCRIPT_NAME};;
			system)
				echo -e "start=\t${PARTITION_START[${i}]}, size=\t${PARTITION_SIZE[${i}]}, type=BC13C2FF-59E6-4262-A352-B275FD6F7172, attrs=LegacyBIOSBootable, name=\"${PARTITION_NAME[${i}]}\", bootable," >> ${SFDISK_SCRIPT_NAME};;
			filesystem)
				echo -e "start=\t${PARTITION_START[${i}]}, size=\t${PARTITION_SIZE[${i}]}, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"${PARTITION_NAME[${i}]}\"" >> ${SFDISK_SCRIPT_NAME};;
			shadow)
				;;
			*)
				echo "Error : Unknow partition type ${PARTITION_TYPE[${i}]}"
				clean_env 3;;
		esac
	done
	#echo -e "start=\t194000, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name=\"pacing part\"" >> ${SFDISK_SCRIPT_NAME}
}

function add_dos_partition () {
	for ((i=0;i<TOTAL_OF_PARTITION;i++))
	do
		case ${PARTITION_TYPE[${i}],,} in
			binary)
				echo -e "start=\t${PARTITION_START[${i}]}, size=\t${PARTITION_SIZE[${i}]}, type=8DA63339-0007-60C0-C436-083AC8230908, name=\"${PARTITION_NAME[${i}]}\"" >> ${SFDISK_SCRIPT_NAME};;
			system)
				echo -e "start=\t${PARTITION_START[${i}]}, size=\t${PARTITION_SIZE[${i}]}, type=c, name=\"${PARTITION_NAME[${i}]}\"" >> ${SFDISK_SCRIPT_NAME};;
			filesystem)
				echo -e "start=\t${PARTITION_START[${i}]}, size=\t${PARTITION_SIZE[${i}]}, type=83, name=\"${PARTITION_NAME[${i}]}\"" >> ${SFDISK_SCRIPT_NAME};;
			shadow)
				;;
			*)
				echo "Error : Unknow partition type ${PARTITION_TYPE[${i}]}"
				clean_env 3;;
		esac
	done
}

function create_partition_table () {


	#write sfdisk partition file header 
	echo -e "label:${PARTITION_TABLE_TYPE}\nfirst-lba:${FIRST_SECTOR}\n" > ${SFDISK_SCRIPT_NAME}

	case ${PARTITION_TABLE_TYPE,,} in
		gpt)
			add_gpt_partition;;
		dos)
			add_dos_partition;;
		*)
			echo "Error : ${PARTITION_TABLE_TYPE} partition not supported yet (or maybe mispelled, supported types are : ${SUPPORTED_PARTITION_TABLE})"
			clean_env 2;;
	esac

	#Write the partition table using sfdisk
	sfdisk ${SDCARD_FILENAME} < ${SFDISK_SCRIPT_NAME}

	if [ $? -ne 0 ] ; then
		echo "Error : It seems that something went wrong with sfdisk, check the sfdisk output to find more"
		clean_env 1
	fi
}

function populate_partition_table () {
	
	if [ -f "${SOURCE}" ] ; then
		SOURCE="${SOURCE}/"
	fi

	for ((i=0;i<TOTAL_OF_PARTITION;i++))
	do
		if [ ! -f "${SOURCE}${PARTITION_FILENAME[${i}]}" ] ; then
			echo "ERROR : ${SOURCE}${PARTITION_FILENAME[${i}]} not found"
			clean_env 4
		fi
		#echo "if [ $((${PARTITION_SIZE[${i}]}*512)) -lt $(echo $( du  ${SOURCE}${PARTITION_FILENAME[${i}]} ) | sed -e 's/ .*$//') ]"
#set -vx
		if [ $((${PARTITION_SIZE[${i}]}*512)) -lt $(sed -e 's/[^[:digit:]]//g' <<< $(du ${SOURCE}${PARTITION_FILENAME[${i}]})) ] ; then # old $(cut -d " " -f 1 <<< $(du ${SOURCE}${PARTITION_FILENAME[${i}]}))
#set +vx
			echo "ERROR : Partition size : ${PARTITION_SIZE[${i}]} sectors (i.e $((${PARTITION_SIZE[${i}]}*512)) bytes ) seems inferior to partition file size : $(echo $( du  ${SOURCE}${PARTITION_FILENAME[${i}]} ) | sed -e 's/ .*$//') bytes "
			clean_env 9
		fi
		
		echo "Populating partition ${PARTITION_NAME[${i}]} with ${SOURCE}${PARTITION_FILENAME[${i}]} ..."
		echo " dd if=${SOURCE}${PARTITION_FILENAME[${i}]} of=${SDCARD_FILENAME} conv=fdatasync,notrunc seek=${PARTITION_START[${i}]} bs=512"
		dd if=${SOURCE}${PARTITION_FILENAME[${i}]} of=${SDCARD_FILENAME} conv=fdatasync,notrunc seek=${PARTITION_START[${i}]} bs=512 # old version -> seek=1 bs=$((512*${PARTITION_START[${i}]}))
	done
}

#function do_create_sdcard_file () {
set_env

parse_option $@
parse_layout ${LAYOUT_FILE}


if [ "${ONLY_PARSE}" == "true" ] ; then
	clean_env 0
fi 

#validate_layout

create_void_sdcard_file
create_partition_table
populate_partition_table

clean_env 0
#}

#		echo "PARTITION_NAME = ${PARTITION_NAME[${i}]}; PARTITION_START = ${PARTITION_START[${i}]}; PARTITION_SIZE = ${PARTITION_SIZE[${i}]}; PARTITION_TYPE = ${PARTITION_TYPE[${i}]}; PARTITION_FILENAME = ${PARTITION_FILENAME[${i}]}"


