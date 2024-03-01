.PHONY: check_deps build-image create-cluster install-rook-storage ceph-status import-data import-taxonomies install-spark-operator anonymize export_results clean-rook-storage clean-spark-operator clean-minikube remote watch-spark watch-rook


REQUIRED_BINS	:= docker kubectl helm

SPARK_IMAGE_TAG := latest
SPARK_IMAGE := kube-mondrian:${SPARK_IMAGE_TAG}

PACKAGE			:= mondrian
PACKAGE_ZIP		:= $(PACKAGE).zip
OUTPUT_DIR		:= anonymized


check_deps:
	$(foreach bin,$(REQUIRED_BINS),\
		$(if $(shell which $(bin)),,$(error Please install `$(bin)`)))


build-image:
	zip -r ${PACKAGE_ZIP} ./${PACKAGE}
	docker build -t ${SPARK_IMAGE} .
	rm ${PACKAGE_ZIP}


create-cluster:
# create single node minikube cluster
	minikube start --driver kvm2 --cpus 2 --memory 2200m --extra-disks 1 --disk-size 10g
# import image
	minikube image load ${SPARK_IMAGE}
# import image (alternative)
#	docker save --output kube-mondrian.img ${SPARK_IMAGE}
#	minikube image load kube-mondrian.img


install-rook-storage:
# deploy rook operator and custom resources
	kubectl create -f ./rook/crds.yaml -f ./rook/common.yaml -f ./rook/operator.yaml
# create ceph cluster
	kubectl create -f ./rook/cluster-single-node.yaml
# create shared filesystem
	kubectl create -f ./rook/filesystem-single-node.yaml
# create storage class
	kubectl create -f ./rook/storageclass.yaml
# create rook toolbox
	kubectl create -f ./rook/toolbox.yaml

ceph-status:
	kubectl exec -it deploy/rook-ceph-tools -n rook-ceph -- ceph status


import-data:
# create shared pvc
	kubectl create -f ./rook/cephfs-pvc.yaml
# create data transfer pod
	kubectl create -f ./deploy/data-transfer.yaml
# wait till data transfer pod is in Running state
#	kubectl wait --for=jsonpath='{.status.phase}'=Running pod/data-transfer-pod
# create directories in ceph file system
	kubectl exec -it data-transfer-pod -- mkdir /data/config /data/dataset /data/taxonomy /data/anonymized /data/spark-events
# import files
	kubectl cp -n default ./config/adults.json data-transfer-pod:/data/config/adults.json
	kubectl cp -n default ./dataset/adults.csv data-transfer-pod:/data/dataset/adults.csv
	kubectl cp -n default ./config/poker.json data-transfer-pod:/data/config/poker.json
	kubectl cp -n default ./dataset/poker.csv data-transfer-pod:/data/dataset/poker.csv
	kubectl cp -n default ./taxonomy/countries.json data-transfer-pod:/data/taxonomy/countries.json
	kubectl cp -n default ./taxonomy/us.json data-transfer-pod:/data/taxonomy/us.json
#	kubectl exec -it data-transfer-pod -- /bin/bash
# delete data transfer pod
	kubectl delete -f ./deploy/data-transfer.yaml

import-taxonomies:
# automatic alternative to import all files in a local directory
	$(foreach f, $(wildcard taxonomy/*), $(shell kubectl cp -n default ./$f data-transfer-pod:/data/$f))


install-spark-operator:
# add spark operator helm repo
	helm repo add spark-operator https://googlecloudplatform.github.io/spark-on-k8s-operator
	helm repo update
# install spark operator
	helm install spark-operator spark-operator/spark-operator \
		--namespace spark-operator --create-namespace \
		--set sparkJobNamespace=default \
		--set webhook.enable=true


anonymize:
#	kubectl apply -f ./deploy/kube-mondrian-adults.yaml
	kubectl apply -f ./deploy/kube-mondrian-poker.yaml
	kubectl logs kube-mondrian-driver
#	kubectl delete -f ./deploy/kube-mondrian-adults.yaml
	kubectl delete -f ./deploy/kube-mondrian-poker.yaml


export_results:
	mkdir -p ${OUTPUT_DIR}
	kubectl create -f ./remote/deploy/data-transfer.yaml
# export files	
#	kubectl cp -n default data-transfer-pod:/data/anonymized/adults.csv ./anonymized/adults.csv
	kubectl cp -n default data-transfer-pod:/data/anonymized/poker.csv ./anonymized/poker.csv
#	kubectl cp -n default data-transfer-pod:/data/anonymized/test_results.csv ./anonymized/test-results.csv
#	kubectl cp -n default data-transfer-pod:/data/anonymized/artifact_result.csv ./anonymized/artifact-result.csv
# delete data transfer pod and shared pvc
	kubectl delete -f ./remote/deploy/data-transfer.yaml
	kubectl delete -f ./remote/deploy/cephfs-pvc.yaml


clean-rook-storage:
	kubectl delete -f ./remote/rook/toolbox.yaml
	kubectl delete -f ./remote/rook/storageclass.yaml
	kubectl -n rook-ceph delete cephfilesystem myfs
	kubectl -n rook-ceph patch cephcluster my-cluster --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'
	kubectl -n rook-ceph delete cephcluster my-cluster
#	kubectl -n rook-ceph get cephcluster
	kubectl delete -f ./remote/rook/crds.yaml -f ./remote/rook/common.yaml -f ./remote/rook/operator.yaml
	
clean-spark-operator:	
	helm uninstall spark-operator -n spark-operator
	helm repo remove spark-operator

clean-minikube:
	minikube ssh "sudo rm -rf /data/rook"
	minikube delete


watch-spark:
	watch -n 5 kubectl get pods -o wide

watch-rook:
	watch -n 10 kubectl get pods -n rook-ceph -o wide



remote:
# install rook operator and ceph storage
	kubectl create -f ./rook/crds.yaml -f ./rook/common.yaml -f ./rook/operator.yaml
	kubectl create -f ./rook/cluster-remote.yaml
	kubectl create -f ./rook/filesystem-remote.yaml
	kubectl create -f ./rook/storageclass.yaml
	kubectl create -f ./rook/toolbox.yaml
# import data
	kubectl create -f ./rook/cephfs-pvc.yaml
	kubectl create -f ./deploy/data-transfer.yaml
	kubectl exec -it data-transfer-pod -- mkdir /data/config /data/dataset /data/taxonomy /data/anonymized /data/spark-events
	kubectl cp -n default ./config/adults.json data-transfer-pod:/data/config/adults.json
	kubectl cp -n default ./dataset/adults.csv data-transfer-pod:/data/dataset/adults.csv
	kubectl cp -n default ./config/poker.json data-transfer-pod:/data/config/poker.json
	kubectl cp -n default ./dataset/poker.csv data-transfer-pod:/data/dataset/poker.csv
	kubectl cp -n default ./taxonomy/countries.json data-transfer-pod:/data/taxonomy/countries.json
	kubectl cp -n default ./taxonomy/us.json data-transfer-pod:/data/taxonomy/us.json
	kubectl exec -it data-transfer-pod -- /bin/bash
	kubectl delete -f ./deploy/data-transfer.yaml
# install spark operator
	helm repo add spark-operator https://googlecloudplatform.github.io/spark-on-k8s-operator
	helm repo update
	helm install spark-operator spark-operator/spark-operator \
		--namespace spark-operator --create-namespace \
		--set sparkJobNamespace=default \
		--set webhook.enable=true
# execute spark app
	kubectl apply -f ./deploy/kube-mondrian-adults.yaml
	kubectl apply -f ./deploy/kube-mondrian-poker.yaml
	kubectl logs kube-mondrian-driver
	kubectl delete -f ./deploy/kube-mondrian-adults.yaml
	kubectl delete -f ./deploy/kube-mondrian-poker.yaml
# export results
	mkdir -p ${OUTPUT_DIR}
	kubectl create -f ./remote/deploy/data-transfer.yaml
	kubectl cp -n default data-transfer-pod:/data/anonymized/adults.csv ./anonymized/adults.csv
	kubectl cp -n default data-transfer-pod:/data/anonymized/poker.csv ./anonymized/poker.csv
	kubectl cp -n default data-transfer-pod:/data/anonymized/test_results.csv ./anonymized/test-results.csv
	kubectl cp -n default data-transfer-pod:/data/anonymized/artifact_result.csv ./anonymized/artifact-result.csv
	kubectl delete -f ./deploy/data-transfer.yaml
	kubectl delete -f ./rook/cephfs-pvc.yaml
# remove rook and spark
	kubectl delete -f ./rook/toolbox.yaml
	kubectl delete -f ./rook/storageclass.yaml
	kubectl delete -f ./rook/filesystem-remote.yaml
	kubectl -n rook-ceph patch cephcluster my-cluster --type merge -p '{"spec":{"cleanupPolicy":{"confirmation":"yes-really-destroy-data"}}}'
	kubectl -n rook-ceph delete cephcluster my-cluster
	kubectl -n rook-ceph get cephcluster
	kubectl delete -f ./remote/rook/crds.yaml -f ./remote/rook/common.yaml -f ./remote/rook/operator.yaml
	helm uninstall spark-operator -n spark-operator
	helm repo remove spark-operator
