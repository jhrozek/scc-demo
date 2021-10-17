# SELinux, seccomp and SCCs: a demo

## What is this work about?

Our team (ISC, for some reason using the CMP project in Jira) works primarily
on making OpenShift compliant with variours security standards, but also
generally speaking on securing OpenShift. 

Our team is concerned about the number of privileged containers in OpenShift.
In order to reduce the number, we have been working on Security Profiles
Operator which allows the administrator to deploy and manage SELinux and seccomp
profiles as k8s native objects.

This demo is meant to show the current state and the challenges we face
when deploying SELinux and seccomp profiles in OpenShift, especially
those related to SCCs.

This repo is adjusted from a previous demo Juan Antonio Osorio gave to
the SELinux team, with minor changes.

## Demo setup

* Install the SPO from its repo with 'make deploy-openshift-dev'
* Enable SELinux with 'oc patch spod/spod -p '{"spec":{"enableLogEnricher": true, "enableSelinux":true}}' --type=merge'

* From this repo, run the `make setup` target. This will set up an
  appropriate namespace and the needed security profile as well as
  an IdP with non-kubeadmin users.

## Instructions

Look at the target application in `main.go`. This app that we want to deploy is
quite simple. It merely is a go application that writes its logs to the
specific node. You can image a similar workload which would instead read the
nodes' logs and forward them to a secure location.

You'll note that the aforementioned `setup` target already uploaded it to its
appropriate namespace in OpenShift's image registry. We can now take it into
use!

### 01-demo-pod-defaults-too-strict.yaml:

doesn't work SELinux blocks access to files
  labeled with var_log_t from a container labeled with container_t

```
oc apply -f 01-demo-pod-defaults-too-strict.yaml
```

You'll notice that the workload failed. Let's take a look:

```
$ oc logs demo
Unable to open log file: open /log/demologs.log: permission denied
```

This is to be expected! Accessing a host is a privileged operation, and so, a
regular workload is not able to do this. We could simply set the `privileged`
flag in the pod's `securityContext` section to `true`. But we shouldn't do
this, as it would give too much access to the host itself...

### 02-demo-pod-spc_t-too-open.yaml

We can also give the SA the permissions to use an SCC that allows us to mount
a host filesystem. This would still not help completely, because the files
from the host are labaled as 'var_log_t', but the container is running as
'container_t'. The easiest, but least secure way is to run the container
as the 'spc_t' type, effectively an 'unconfined_t' in the container world.

Moreover, the fact that we had to give the SA permissions to use the privileged
SCC is not great either as the privileged SCC allows the container to run as any
UID and use any capabilities.

### 03-demo-pod-secure.yaml

This pod uses the 'errorlogger_scc-demo.process' SELinux policy that we prepared
for this demo. It only allows access to files and directories labeled 'var_log_t'.
So this is reasonably secure and could be paired with a seccomp policy to make
sure that the workload is only allowed to call certain syscalls.

We finally come to the problem I wanted to point out during the demo. In order to
use the custom SELinux policy, we had to allow the SA to use the privileged SCC,
as all the other SCCs use the MustRunAs strategey for SELinux.

* 04-demo-pod-badpod.yaml: negative test of SELinux: don't allow audit_t files

## Problem statement

While OpenShift allows the user to set different SELinux contexts and seccomp profiles,
the management is too coarse, especially on the SCC level.

Let's look at both SELinux and seccomp separately:
    - SELinux: there's only MustRunAs or RunAsAny, so we either give the admin the option
      to run with the scc.mcs levels in the namespace or as any context. There's no option
      to say "I only want this subset of contexts to be allowed"
    - seccomp: Not handled with SCCs at all, anything goes if the admin has the privilege
      to set a seccomp context

Setting RunAsAny is also, by default, only allowed with the privileged or node-exporter
SCCs which open up many other options such as all capabilities, running containers in
privileged mode and so on. At the same time, there is no (AFAICT?) way to limit the use
of SAs in the namespace, so once someone has the privileges to run pods in a namespace
that contains such elevated SA, they can run pretty much without any security constraints.

Because the security policies are supposed to be bound to workloads which are normally
namespaces, the security policies in SPO are namespaced as well:

```
oc get selinuxprofiles
```

What we would like to achieve is the following: have a way to only allow
a workload to use a subset of the existing security profiles, typically
those that are installed in the namespace without giving the workload the
full privileged SCC rights.

## Proposed solution

Note that the following is just a proposal. We don't claim in any way to be experts
in SCCs or the API server at all.

A new MustRunAsRange strategy for SELinux could be added. This strategy would only
allow using SELinux contexts that are listed as annotations in the namespace where
the workload is running, similar to how the MustRunAsRange strategy works for UIDs
or supplemental GIDs. A mechanism would have to be implemented to allow updating
the annotations by a trusted workload such as the SPO (although this is not tied
to the SPO per se).

Using this MustRunAsRange strategy, a new default SCC (let's call it 'restricted')
could be added that acts as the anyuid SCC, but allows the MustRunAsRange SELinux
strategy. Other SCCs could be added by the administrator depending on the needs,
e.g. depending on what volumes must be used or what UIDs must be used.

## Contingency plan

As a contingency plan, we could instruct the SPO users (or really, anyone wishing
to use their own SCCs) to create a new SCC that would use the 'RunAsAny' strategy
for SELinux. This does not solve the issue of restricting workloads in a namespace
to a subset of the existing policies, but instead still allows any. No engineering
work is needed, though.

## Links
https://github.com/openshift/enhancements/pull/745 - SPO OpenShift enhancement
https://github.com/kubernetes-sigs/security-profiles-operator - SPO github project

Find us at `forum-compliance` on the CoreOS Slack.
