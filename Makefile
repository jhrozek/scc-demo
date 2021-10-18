IMAGE:=demo:latest
NAMESPACE:=scc-demo

.PHONY: build
build: demo

demo: main.go
	go build -o demo main.go

.PHONY: image
image:
	podman build -t $(IMAGE) -f Dockerfile .

.PHONY: setup
setup: ns image openshift-user idp
	@echo "Exposing the default route to the image registry"
	@oc patch configs.imageregistry.operator.openshift.io/cluster --patch '{"spec":{"defaultRoute":true}}' --type=merge
	@echo "Pushing image $(IMAGE) to the image registry"
	@IMAGE_REGISTRY_HOST=$$(oc get route default-route -n openshift-image-registry --template='{{ .spec.host }}'); \
		podman login --tls-verify=false -u $(OPENSHIFT_USER) -p $(shell oc whoami -t) $${IMAGE_REGISTRY_HOST}; \
		podman push --tls-verify=false localhost/$(IMAGE) $${IMAGE_REGISTRY_HOST}/$(NAMESPACE)/$(IMAGE)
	@echo "Creating seccomp profile"
	@oc apply -f baseprofile.yaml
	@oc apply -f seccompprofile.yaml
	@echo "Creating selinux profile"
	@oc apply -f selinuxpolicy.yaml
	@echo "Creating RBAC"
	@oc apply -f role.yaml
	@oc apply -f role_binding.yaml
	@oc apply -f sa.yaml

ns:
	@oc apply -f ns.yaml
	@oc project $(NAMESPACE)

idp: ns
	@echo "Creating htpasswd DB"
	@htpasswd -c -B -b users.htpasswd user1 Secret123
	@htpasswd -b users.htpasswd user2 Secret123
	@echo "Creating htpasswd IDP"
	@oc create secret generic htpass-secret --from-file=htpasswd=./users.htpasswd -n openshift-config
	@oc apply -f htpasswd-idp.yaml
	@rm -f users.htpasswd
	@echo "Allowing user1 into the project"
	@oc project scc-demo
	@oc adm policy add-role-to-user edit user1

.PHONY: openshift-user
openshift-user:
ifeq ($(shell oc whoami 2> /dev/null),kube:admin)
	$(eval OPENSHIFT_USER = kubeadmin)
else
	$(eval OPENSHIFT_USER = $(shell oc whoami))
endif
