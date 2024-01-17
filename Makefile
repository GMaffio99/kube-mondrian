.PHONY: all check_deps clean rook rook-toolbox ceph-status delete-rook start-app stop-app create-cluster start-cluster stop-cluster delete-cluster

REQUIRED_BINS	:= docker kubectl helm k3d

PACKAGE			:= mondrian
PACKAGE_ZIP		:= $(PACKAGE).zip
OUTPUT_DIR		:= anonymized

SPARK_IMAGE_TAG	:= latest
SPARK_IMAGE		:= pyspark-mondrian:${SPARK_IMAGE_TAG}

CLUSTER			:= mondrian-cluster
NUM_SERVERS		:= 1
NUM_AGENTS		:= 3

all:
# create spark image
	zip -r ${PACKAGE_ZIP} ./${PACKAGE}
	docker build -t ${SPARK_IMAGE} .
	rm ${PACKAGE_ZIP}
# create k3d cluster
	mkdir -p ${OUTPUT_DIR}
	k3d cluster create ${CLUSTER} \
		--servers ${NUM_SERVERS} \
		--agents ${NUM_AGENTS} \
		--kubeconfig-update-default \
		--volume "$(shell pwd)/config:/data/config" \
		--volume "$(shell pwd)/dataset:/data/dataset" \
		--volume "$(shell pwd)/taxonomy:/data/taxonomy" \
		--volume "$(shell pwd)/anonymized:/data/anonymized"
# import spark image into the k3d cluster
	k3d image import ${SPARK_IMAGE} -c ${CLUSTER}
# install spark operator
	helm repo add spark-operator https://googlecloudplatform.github.io/spark-on-k8s-operator
	helm install spark-operator spark-operator/spark-operator \
		--namespace spark-operator --create-namespace \
		--set sparkJobNamespace=default \
		--set webhook.enable=true
# run spark job
	kubectl apply -f deploy/spark-mondrian-storage.yaml
	kubectl apply -f deploy/spark-mondrian.yaml

check_deps:
	$(foreach bin,$(REQUIRED_BINS),\
		$(if $(shell which $(bin)),,$(error Please install `$(bin)`)))

clean:
# delete spark operator
	kubectl delete -f deploy/spark-mondrian.yaml
	helm uninstall spark-operator -n spark-operator
	helm repo remove spark-operator
# delete k3d cluster
	k3d cluster delete ${CLUSTER}
# remove spark images
	docker rmi ${SPARK_IMAGE}


rook:
# clone rook repo
	mkdir tmp
	git clone --single-branch --branch v1.13.1 https://github.com/rook/rook.git ./tmp/rook/
# create cluster on KVM
#	minikube start --driver kvm2 --nodes 4 --extra-disks 2 --disk-size 30g
	export NO_PROXY=localhost,127.0.0.1,10.96.0.0/12,192.168.59.0/24,192.168.49.0/24,192.168.39.0/24 & \
	minikube start --driver kvm2 --cpus max --extra-disks 3 --disk-size 40g
# deploy rook operator
	kubectl create -f ./tmp/rook/deploy/examples/crds.yaml -f ./tmp/rook/deploy/examples/common.yaml -f ./tmp/rook/deploy/examples/operator.yaml
# create ceph cluster
	kubectl create -f ./tmp/rook/deploy/examples/cluster-test.yaml
#	kubectl create -f ./tmp/rook/deploy/examples/cluster-on-pvc-minikube.yaml
# create shared filesystem
#	kubectl create -f ./tmp/rook/deploy/examples/filesystem-test.yaml
# create storage class
#	kubectl create -f ./tmp/rook/deploy/examples/csi/cephfs/storageclass.yaml
# create example pvc and pod
#	kubectl create -f ./tmp/rook/deploy/examples/csi/cephfs/pvc.yaml -f ./tmp/rook/deploy/examples/csi/cephfs/pod.yaml

rook-toolbox:
	kubectl create -f ./tmp/rook/deploy/examples/toolbox.yaml

ceph-status:
	kubectl exec -it deploy/rook-ceph-tools -n rook-ceph -- ceph status

delete-rook:
	kubectl delete deployment rook-ceph-tools -n rook-ceph
#	kubectl delete cephfilesystem myfs -n rook-ceph
	kubectl delete -f ./tmp/rook/deploy/examples/cluster-test.yaml
	kubectl delete -f ./tmp/rook/deploy/examples/crds.yaml -f ./tmp/rook/deploy/examples/common.yaml -f ./tmp/rook/deploy/examples/operator.yaml
	rm -rf ./tmp



start-app:
	kubectl apply -f deploy/spark-mondrian.yaml

stop-app:
	kubectl delete -f deploy/spark.mondrian.yaml

create-cluster:
	k3d cluster create ${CLUSTER} --servers ${NUM_SERVERS} --agents ${NUM_AGENTS} --kubeconfig-update-default

start-cluster:
	k3d cluster start ${CLUSTER}

stop-cluster:
	k3d cluster stop ${CLUSTER}

delete-cluster:
	k3d cluster delete ${CLUSTER}

