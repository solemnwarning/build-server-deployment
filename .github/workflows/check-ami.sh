#!/bin/bash

if [ "$#" -ne 1 ]
then
	echo "Usage: $0 <image name (prefix)>" 1>&2
	exit 64 # EX_USAGE
fi

branch_name="${GITHUB_REF#refs/heads/}"
echo "On branch $branch_name"
echo ::set-output name=branch_name::$branch_name

dir_sha=$(git log --pretty='format:%h' -1 -- "$1")
echo "Directory $1 is at $dir_sha"
echo ::set-output name=dir_sha::$dir_sha

# If we're running on master, check that a recent (within 28 days) master image
# exists. If on a topic branch, a build from any branch with the same SHA will
# do, since its only for (manual) testing.

MAX_MASTER_AGE=$[ 60 * 60 * 24 * 28 ]

if [ "$branch_name" = "master" ]
then
	ami_name_filter="$1-master-${dir_sha}-*"
else
	ami_name_filter="$1-*-${dir_sha}-*"
fi

ami_names=$(aws ec2 describe-images --owners self --filters "Name=name,Values=${ami_name_filter}" | jq -r '.Images[].Name')
ami_count=$(wc -l <<< "${ami_names}")
ami_ok=false

echo "Found ${ami_count} AMIs matching expression '${ami_name_filter}':"

for ami_name in ${ami_names}
do
	# Extract date/time from AMI as "YYYYMMDD HH:MM:SS"
	ami_date=$(sed -Ee 's/^.*-([0-9]{8})-([0-9]{2})([0-9]{2})([0-9]{2})$/\1 \2:\3:\4/' <<< "$ami_name")
	
	# ...convert to UNIX timestamp
	ami_timestamp=$(TZ=UTC date --date="${ami_date}" +%s)
	
	# ...subtract from current time to find age
	ami_age_secs=$[ $(date +%s) - ${ami_timestamp} ]
	
	echo "- ${ami_name} (built ${ami_age_secs} seconds ago)"
	
	if [ "$branch_name" = "master" ]
	then
		if [ "${ami_age_secs}" -le "${MAX_MASTER_AGE}" ]
		then
			ami_ok=true
		fi
	else
		ami_ok=true
	fi
done

if [ "$ami_ok" = "true" ]
then
	echo ::set-output name=build_ami::false
else
	echo ::set-output name=build_ami::true
fi
