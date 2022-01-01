# Kubelet systemd portable service image

["Portable Services"](https://systemd.io/PORTABLE_SERVICES/) are a new
feature in systemd v239.  They allow you to bundle a systemd service
into an easily-installed image, similar to containers but with some
important differences.

This project builds a portable service image that contains kubelet and
container runtime (CRI-O).  This allows kubelet to be easily installed
and upgraded on any base OS that uses systemd.

## Usage

Download the image for your architecture from the releases page, and
then install using `portablectl`.

```sh
# portablectl may not be installed by default. Eg, for Debian:
apt install systemd-container

# portablectl recommends /var/lib/portables/
mv kubelet_1.22.1.raw /var/lib/portables/

portablectl attach --profile=trusted --enable --now kubelet_1.22.1.raw
```

## Is this just another containerised kubelet?

No!

Kubelet in a container looks like this:

```
Base OS (systemd/sysvinit/other)
 -> container runtime (docker/containerd/crio/rkt)
    -> kubelet
    -> pods
```

But kubelet portable service image looks like this:

```
Base OS (systemd)
 -> portable service chroot
    -> kubelet
    -> container runtime (docker/containerd/crio/rkt)
       -> pods
```

Importantly, with a portable service image the kubelet and container
runtime are 'siblings' and share the same view of the system.  Eg: if
a device plugin pod manipulates the service chroot filesystem, then
kubelet sees this too.

The kubelet and runtime dependencies are bundled in the portable
service image, and can be easily installed/upgraded separate to the
base OS.  All the benefits of a containerised kubelet, without the
downsides.

## Contributing

This package builds using BuildKit.

```sh
docker buildx build \
    --platform=linux/amd64,linux/arm64 \
    --cache-to=type=local,dest=/tmp/buildcache \
    --cache-from=type=local,src=/tmp/buildcache \
    --target final-squashfs \
    -o type=local,dest=/tmp/output

# squashfs output images are in /tmp/output/
```

For debugging, just looking at the root filesystem is also
interesting:

```sh
docker buildx build \
    --platform=linux/amd64 \
    --cache-to=type=local,dest=/tmp/buildcache \
    --cache-from=type=local,src=/tmp/buildcache \
    --target final \
    -o type=local,dest=/tmp/rootfs

# filesystem is copied to /tmp/rootfs/
```
