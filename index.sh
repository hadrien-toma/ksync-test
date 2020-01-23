#!/bin/bash

#region cluster configuration
cpus="6"
kubernetesVersion="v1.17.0"
memory="32768"
vmDriver="kvm2"
#endregion

#region traps
trap 'sigintTrap' 2

sigintTrap() {
	if [ "${pids}X" != "X" ]; then
		echo "pids=${pids}"
		kill -9 ${pids}
	fi
	exit 2
}
#endregion

#region versions
echo "uname -a -> `uname -a`"
echo ""
echo "BASH_VERSION -> ${BASH_VERSION}"
echo ""
echo "ksync version -> `ksync version`"
echo ""
echo "kubectl version -> `kubectl version`"
echo ""
echo "minikube version -> `minikube version`"
echo ""
#endregion

#region hereDir
hereDir=`dirname $0 | while read a; do cd $a && pwd && break; done `
#endregion

#region inputs
activeDeadlineSeconds=${1:-"180"}
minDirsCount=${2:-"2"}
maxDirsCount=${3:-"5"}
minFilesCount=${4:-"8"}
maxFilesCount=${5:-"10"}
minJobsCount=${6:-"1"}
maxJobsCount=${7:-"3"}
#endregion

#region reset results files system
rm -rf ${hereDir}/results
mkdir ${hereDir}/results
echo "dirsCount,filesCount,jobsCount,jobsCompletionRate" > ${hereDir}/results/summary.txt
#endregion

for dirsCount in `seq ${minDirsCount} ${maxDirsCount}`; do
	for filesCount in `seq ${minFilesCount} ${maxFilesCount}`; do
		for jobsCount in `seq ${minJobsCount} ${maxJobsCount}`; do
			#region reset processings
			kill -9 ${pids}
			#endregion

			#region reset files system
			rm -rf ${hereDir}/base ${hereDir}/list ${hereDir}/watch.err ${hereDir}/watch.out
			mkdir ${hereDir}/base ${hereDir}/list
			for dir in `seq 1 ${dirsCount}`; do
				mkdir ${hereDir}/list/${dir}
				for file in `seq 1 ${filesCount}`; do
					touch ${hereDir}/list/${dir}/${file}.txt
				done
			done
			ls ${hereDir}/list > ${hereDir}/base/index.txt
			#endregion

			#region reset cluster
			minikube delete
			minikube start --cpus=${cpus} --kubernetes-version=${kubernetesVersion} --memory=${memory} --vm-driver=${vmDriver}
			minikube tunnel > logs/tunnel.out 2> logs/tunnel.err &
			pids="${pids} $!"
			kubectl create namespace ksync-test
			#endregion

			#region reset ksync
			ksync delete --all
			ksyncPids=`ps -xao pid,cmd | grep "ksync watch" | grep --invert-match "grep" | sed 's/^\( *\) //g' | cut --delimiter=' ' --fields=1 | tr '\n' ' '`
			kill -9 ${ksyncPids}
			rm -rf ~/.ksync/ksync.yaml ~/.ksync/syncthing ~/.ksync/syncthing.pid
			ksync init
			ksync watch --log-level debug --namespace ksync-test > ${hereDir}/results/watch--${dirsCount}--${filesCount}--${jobsCount}.out 2> ${hereDir}/results/watch--${dirsCount}--${filesCount}--${jobsCount}.err &
			pids="${pids} $!"
			#endregion

			#region requests of execution
			for job in `seq 1 ${jobsCount}`; do
				jobName="${dirsCount}-${filesCount}-${jobsCount}--${job}"
				echo "jobName=${jobName}"
				cat <<EOF | kubectl apply --force -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: ksync-test-job-${jobName}
  namespace: ksync-test
spec:
  activeDeadlineSeconds: ${activeDeadlineSeconds}
  template:
    metadata:
      name: ksync-test-job-${jobName}
      namespace: ksync-test
    spec:
      containers:
      - command:
        - /bin/ash
        - "-c"
        - |
          /bin/ash <<'EOF'

          while [ ! -f /base/index.txt ]; do
              echo \$(date)" Waiting /base/index.txt synchronization"
              sleep 1
          done
          echo "Synced with /base/index.txt"

          list=\$(cat /base/index.txt | tr '\n' ' ')
          for item in \${list}; do
              for file in \$(seq 1 ${filesCount}); do
                while [ ! -f /list/\${item}/\${file}.txt ]; do
                    echo \$(date)" Waiting /list/\${item}/\${file}.txt synchronization"
                    sleep 1
                done
                echo "Synced with /list/\${item}/\${file}.txt"
              done
          done

          echo "🎉"
          EOF
        image: alpine:latest
        name: ksync-test-job-${jobName}
        resources:
          limits:
            cpu: 3
          requests:
            cpu: 1500m
      restartPolicy: OnFailure
EOF
				#endregion

				#region requests of synchronization
				podName=`kubectl get pods --namespace ksync-test --selector=job-name=ksync-test-job-${jobName} --output=jsonpath="{.items[0].metadata.name}"`
				echo "podName=${podName}"

				kubectl wait --for=condition=Initialized --namespace ksync-test --timeout=2m pod/${podName} \
				&& \
				ksync create --namespace ksync-test --pod "${podName}" --container ksync-test-job-${jobName} --reload=false "${hereDir}/base" "/base"

				list=$(cat ${hereDir}/base/index.txt | tr '\n' ' ')
				for item in ${list}; do
					kubectl wait --for=condition=Initialized --namespace ksync-test --timeout=2m pod/${podName} \
					&& \
					ksync create --namespace ksync-test --pod "${podName}" --container ksync-test-job-${jobName} --reload=false "${hereDir}/list/${item}" "/list/${item}"
				done
				#endregion
			done
			#endregion

			#region results
			sleep ${activeDeadlineSeconds}
			completedJobsCount=`kubectl get jobs.batch -n ksync-test | grep "1/1" | wc -l`
			echo "completedJobsCount=${completedJobsCount}"
			jobsCompletionRate=`echo "scale=2 ; ${completedJobsCount} / ${jobsCount}" | bc`
			echo "${dirsCount},${filesCount},${jobsCount},${jobsCompletionRate}" >> ${hereDir}/results/summary.txt
			#endregion
		done
	done
done
