#!/bin/bash

if [ "$#" -ne 1 ]
then
	echo "Usage: $0 <image name (prefix)>" 1>&2
	exit 64 # EX_USAGE
fi

branch_name="${GITHUB_REF#refs/heads/}"
echo "On branch $branch_name"
echo ::set-output name=branch_name::$branch_name

dir_sha=$(git log --pretty='format:%h' -1 "$1")
echo "Directory $1 is at $dir_sha"
echo ::set-output name=dir_sha::$dir_sha

# If we're running on master, check that a master image exists. If on a topic branch, a build from
# any branch with the same SHA will do, since its only for (manual) testing.

if [ "$branch_name" = "master" ]
then
	ami_name_filter="$1-master-${dir_sha}-*"
else
	ami_name_filter="$1-*-${dir_sha}-*"
fi

ami_count=$(aws ec2 describe-images --owners self --filters "Name=name,Values=${ami_name_filter}" | jq '.Images | length')

echo "Found ${ami_count} AMIs matching expression '${ami_name_filter}'"

if [ "$ami_count" -gt 0 ]
then
	echo ::set-output name=build_ami::false
else
	echo ::set-output name=build_ami::true
fi
