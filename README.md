pth is a Pod Troubleshooting Helper for Kubernetes.

('A`) .oO( I'm waiting for [Debug Containers feature](https://github.com/kubernetes/features/issues/277). )


# License

MIT License


# Requirements

- Commands
  - kubectl
  - jq
  - column
- Configurations
  - Privileged mode permission (--allow-privileged=true)


# Usage

```
$ ./pth SUBCOMMAND OPTION
  SUBCOMMAND:
    ls|list          list containers
    exec             create and execute debug pod
    dls|debuglist    list debug pods
    cleanup          cleanup debug pods
    -h|--help        display this message
  OPTION:
    -n <namespace>          kubernetes namespace (default: default)
    --all|--all-namespaces  all namespaces
    -p <name>               target pod name
    -c <name>               targe container name
    -deadline <num>         activeDeadlineSeconds of debug pod (default: 0)
    -image <name>           image name of debug pod (default: albatross0/pth-runc:latest)
    --pull                  set imagePullPolity to Always
    --rootfs                mount node rootfs to debug pod (use this if your container has volumeMounts)
    --no-delete             don't delete debug pod
```

## examples

```
## get pth
$ git clone https://github.com/albatross0/pth.git
$ cd pth

## list containers in all namespaces
$ ./pth ls --all

## execute shell in the target container
## (a debug pod is created in background)
$ ./pth -n <namespace> exec <podname> [-c containername]

## do some work and exit
# ip addr show
# ping 8.8.8.8
# tcpdump -nn -c 50 -i eth0
# exit

## delete debug pods in all namespaces
## (normally they will be deleted automatically on exit)
$ ./pth cleanup --all
```

![](sample_gif/sample1.gif)
![](sample_gif/sample2.gif)
![](sample_gif/sample3.gif)


# Description

pth runs `kubectl create` to create privileged pod,
and then it runs `kubectl exec` to execute shell in the pod.

The pod is associated with pid/net/ipc namespaces of target container and has binaries for troubleshooting such as tcpdump.
(You can create an image of the pod including more binaries.)

Since the pod mounts files and directories used by the target container, you can see files of the target container in `/container` of the pod.


# Customize debug image

```
$ git clone https://github.com/albatross0/pth.git
$ cd pth
$ vi Dockerfile   ## add some lines
$ docker build -t <imagename> .
$ docker push <imagename>

$ ./pth exec <podname> -image <imagename>
```

