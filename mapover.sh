#!/bin/bash

# Not the best bash of the world ... but it works ;)

get_lib_from_maps () {
	echo "[+] Retreive libs from maps files"
	for map in `cat $MAP_FILE`
	do
		#echo "---->  $map  <----"
		name=$(echo "$map" | base64 -w 0 | tr -d "=")
		curl "$map" -H "User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; AS; rv:11.0) like Gecko" 2>/dev/null > ${ROOT_DIR}/maps/$name.map
		# Get modules like @aaaa/bbbb
		cat ${ROOT_DIR}/maps/$name.map | jq ".sources[]" -r | grep -Po 'node_modules\/\K(@[a-zA-Z0-9\-]+\/[a-zA-Z0-9\-]+)' | sort | uniq > "${ROOT_DIR}/maps/$name.dep"
		# Get modules like aaaa
		cat ${ROOT_DIR}/maps/$name.map | jq ".sources[]" -r | grep -Po 'node_modules\/\K([a-zA-Z0-9\-]+)' | sort | uniq >> "${ROOT_DIR}/maps/$name.dep"
	done
	cat ${ROOT_DIR}/maps/*.dep | sort | uniq > ${ROOT_DIR}/all_root_deps.txt
	# Little hack to link with next function in case of recurse=0
	cp ${ROOT_DIR}/all_root_deps.txt ${ROOT_DIR}/dep-of-dep-list.txt
}

get_deps_of_deps () {
	i=$1
	srcfile=$2
	if [ $i -eq 0 ]
	then
		cat ${ROOT_DIR}/dep-of-dep-list* | sort | uniq > "${ROOT_DIR}/all_deps.txt"
		return
	else
		i=$((i-1))
		echo "  --> Get dependencies of dependencies ${i}..."
		echo "" > "${ROOT_DIR}/dep-of-dep-list-${i}.txt"
		echo "" > "${ROOT_DIR}/dep-of-dep-${i}-with-parent.txt"
		for dep in `cat ${ROOT_DIR}/${srcfile}`
		do
			ver=$(curl "https://registry.npmjs.org/$dep"  -H "User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; AS; rv:11.0) like Gecko" 2>/dev/null | jq '."dist-tags".latest')
			curl "https://registry.npmjs.org/$dep"  -H "User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; AS; rv:11.0) like Gecko" 2>/dev/null | jq -r ".versions.$ver.dependencies | keys[] // empty" 2>/dev/null | while read d; 
			do
				echo "$dep:$d" >> "${ROOT_DIR}/dep-of-dep-${i}-with-parent.txt"
				echo "$d" >> "${ROOT_DIR}/dep-of-dep-list-${i}.txt"
			done
			sleep 1
		done
		sort --unique ${ROOT_DIR}/dep-of-dep-list-${i}.txt -o ${ROOT_DIR}/dep-of-dep-list-${i}.txt
		sort --unique ${ROOT_DIR}/dep-of-dep-${i}-with-parent.txt -o ${ROOT_DIR}/dep-of-dep-${i}-with-parent.txt
		get_deps_of_deps $i dep-of-dep-list-${i}.txt 
	fi
}

get_email_from_libs () {
	echo "[+] Retreive all lib emails"
	echo "" > ${ROOT_DIR}/dep-email.txt
	for dep in `cat ${ROOT_DIR}/all_deps.txt`
	do
			curl "https://registry.npmjs.org/$dep"  -H "User-Agent: Mozilla/5.0 (Windows NT 6.1; WOW64; Trident/7.0; AS; rv:11.0) like Gecko" 2>/dev/null | jq -r '.versions[].maintainers[].email' | while read i; 
		do
			echo "$dep:$i"
		done >> ${ROOT_DIR}/dep-email.txt
		sleep 1
	done
	sort --unique ${ROOT_DIR}/dep-email.txt -o ${ROOT_DIR}/dep-email.txt
}

get_domain_from_emails () {
	echo "[+] Get domains from emails"
	cat ${ROOT_DIR}/dep-email.txt | cut -d ":" -f2 | cut -d '@' -f2 | sort | uniq > ${ROOT_DIR}/domain_list.txt
}

get_domain_without_a () {
	echo "[+] Get domains without A record"
	domains=$(cat ${ROOT_DIR}/domain_list.txt)
	for domain in $domains
	do
		nbip=$(dig in A $domain +short | wc -l)
		if [ $nbip -eq 0 ]
		then
			echo "$domain"
		fi
	done > ${ROOT_DIR}/domain_no_A.txt
}

get_domain_without_ns () {
	echo "[+] Get domains without NS record"
	domains=$(cat ${ROOT_DIR}/domain_list.txt)
	for domain in $domains
	do
		nbip=$(dig in NS $domain +short | wc -l)
		if [ $nbip -eq 0 ]
		then
			echo "$domain"
		fi
	done > ${ROOT_DIR}/domain_no_NS.txt
}

check_gmails_accounts () {
	echo -n "[+] Check GHunt configuration --> "
	$GHUNT_PYTHON $GHUNT_MAIN email "google@gmail.com" 2>&1 | grep "Creds aren't loaded. Are you logged in" >/dev/null
	if [ $? -eq 0 ]
	then
		echo "FAIL"
		echo "[-] GHunt is not configured, try by yoursef << $GHUNT_PYTHON $GHUNT_MAIN email \"google@gmail.com\" >>"
		exit 0
	else
		echo "OK"
	fi
	echo "[+] Check gmail accounts"
	gmails=$(cat ${ROOT_DIR}/dep-email.txt | cut -d ":" -f2 | grep 'gmail.com' | sort | uniq | tr -d "\"" )
	for gmail in $gmails
	do
		$GHUNT_PYTHON $GHUNT_MAIN email $gmail >/dev/null
		if [ $? -eq 1 ]
		then
			echo $gmail
		fi
	done > ${ROOT_DIR}/non_existing_gmails.txt
}

##############
#### MAIN ####
##############

recursive=1

while getopts o:m:g:p:r:h flag
do
    case "${flag}" in
        o) output=${OPTARG};;
        m) mapsfile=${OPTARG};;
        g) ghunt=${OPTARG};;
        p) pythonghunt=${OPTARG};;
        r) recursive=${OPTARG};;
	h)
		echo "Usage of $0"
		echo "  -o output_dir : will be created if not exists"
		echo "  -m maps_file : A file that contains all the map files to download"
		echo "  -r <0-oo> : to retreive N level en dependencies"
		echo "  -g ghunt-path : path to the GHunt main.py file"
		echo "  -p python-ghunt-folder : python path for ghunt if you are using a venv for exemple"
		echo ""
		echo "Example: $0 -o out -m maps.txt [-r 3] [[-g venv/bin/python] -g GHUNT/main.py]"
		exit 0
	;;
    esac
done

ROOT_DIR=$output
MAP_FILE=$mapsfile
USE_GHUNT=0
GHUNT_PYTHON=$pythonghunt
GHUNT_MAIN=$ghunt

if [ ${#ROOT_DIR} -eq 0 ]
then
	echo "output folder is mandatory"
	exit 1
fi

if [ ${#MAP_FILE} -eq 0 ]
then
	echo "maps file is mandatory"
	exit 1
fi

if [ -n "${recursive//[0-9]}" ]
then
	echo "[-] -r should be a number"
	exit 0
fi

if [ $recursive -lt 0 ]
then
	echo "[-] Recursive should be greater or equal than 0"
	exit 0
fi

if [ ${#GHUNT_MAIN} -ne 0 ]
then
	USE_GHUNT=1
	if [ ${#GHUNT_PYTHON} -eq 0 ]
	then
		# use default python
		GHUNT_PYTHON="python3"
	fi
fi

mkdir -p "${ROOT_DIR}/maps"

get_lib_from_maps
echo "[+] Retreive $recursive level of dependencies"
get_deps_of_deps $recursive "all_root_deps.txt"
get_email_from_libs
get_domain_from_emails
get_domain_without_ns
get_domain_without_a
if [ $USE_GHUNT -eq 1 ]
then
	check_gmails_accounts
fi
echo "[+] Finished"
