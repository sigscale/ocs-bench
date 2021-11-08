# Manage Google Kubernetes Engine (GKE)

## Create a (tiny) GKE Cluster
	$ gcloud container clusters create cluster-1
			--machine-type e2-small \
			--disk-size 10 \
			--num-nodes 3

## Configure `kubectl` to use the Cluster
	$ gcloud container clusters get-credentials cluster-1
	Fetching cluster endpoint and auth data.
	kubeconfig entry generated for cluster-1.

## Delete the GKE Cluster
	$ gcloud container clusters delete cluster-1

