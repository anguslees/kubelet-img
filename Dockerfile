# syntax=docker/dockerfile:1.2

# renovate: datasource=github-releases depName=kubernetes/kubernetes
ARG KUBELET_VERSION=v1.22.4

FROM --platform=$BUILDPLATFORM debian:11.1@sha256:e8c184b56a94db0947a9d51ec68f42ef5584442f20547fa3bd8cbd00203b2e7a AS wget

RUN \
        --mount=type=cache,target=/var/cache/apt \
        --mount=type=cache,target=/var/lib/apt,sharing=locked \
        set -x -e; \
        rm -f /etc/apt/apt.conf.d/docker-clean; \
        echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
        apt-get update -qy; \
        apt-get install -qy wget

FROM --platform=$BUILDPLATFORM wget AS kubelet

ARG TARGETOS
ARG TARGETARCH

ARG KUBELET_VERSION
ENV KUBELET_TGZ=kubernetes-node-${TARGETOS}-${TARGETARCH}.tar.gz
ENV KUBELET_URL=https://dl.k8s.io/${KUBELET_VERSION}/${KUBELET_TGZ}

WORKDIR /tmp
RUN wget --progress=dot:mega:noscroll ${KUBELET_URL}
RUN tar zxvf ${KUBELET_TGZ} kubernetes/node

WORKDIR /out
RUN install -m 755 -d usr/local/bin/
RUN install -m 755 /tmp/kubernetes/node/bin/kubelet usr/local/bin/

FROM --platform=$BUILDPLATFORM wget AS crio

ARG TARGETARCH

# renovate: datasource=github-tags depName=cri-o/cri-o
ENV CRIO_VERSION=v1.22.1
ENV CRIO_TGZ=cri-o.${TARGETARCH}.${CRIO_VERSION}.tar.gz
ENV CRIO_URL=https://storage.googleapis.com/cri-o/artifacts/${CRIO_TGZ}

WORKDIR /tmp
RUN wget --progress=dot:mega:noscroll ${CRIO_URL}
RUN tar zxvf /tmp/${CRIO_TGZ}

WORKDIR /tmp/cri-o
RUN mkdir /out
RUN DESTDIR=/out bash ./install

# Portable service unit files have to use the same prefix ('kubelet')
WORKDIR /out
RUN mv \
        usr/local/lib/systemd/system/crio.service \
        usr/local/lib/systemd/system/kubelet-crio.service

# Portable services don't support drop-ins from the image itself :(
COPY 50-kubelet-img.conf /tmp
RUN cat /tmp/50-kubelet-img.conf >> usr/local/lib/systemd/system/kubelet-crio.service

FROM --platform=$BUILDPLATFORM wget AS crictl

ARG TARGETOS
ARG TARGETARCH

# renovate: datasource=github-releases depName=kubernetes-sigs/cri-tools
ENV CRICTL_VERSION=v1.22.0
ENV CRICTL_TGZ=crictl-${CRICTL_VERSION}-${TARGETOS}-${TARGETARCH}.tar.gz
ENV CRICTL_URL=https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/${CRICTL_TGZ}

WORKDIR /tmp
RUN wget ${CRICTL_URL}

WORKDIR /out/usr/local
RUN tar zxvf /tmp/${CRICTL_TGZ}

FROM --platform=$TARGETPLATFORM debian:11.1@sha256:e8c184b56a94db0947a9d51ec68f42ef5584442f20547fa3bd8cbd00203b2e7a AS final

# CRI-O needs iproute iptables.
# Everything else is kubelet.  TODO: When everyone moves to CSI-only,
# we can drop all the *fsprogs.

RUN \
        --mount=type=cache,target=/var/cache/apt \
        --mount=type=cache,target=/var/lib/apt,sharing=locked \
        set -x -e; \
        rm -f /etc/apt/apt.conf.d/docker-clean; \
        echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
        apt-get update -qy; \
        apt-get install -qy --no-install-recommends \
        systemd iproute2 iptables conntrack ebtables ipset kmod netbase \
        coreutils ethtool udev socat \
        e2fsprogs ceph-common cifs-utils xfsprogs glusterfs-client nfs-common

COPY --from=crio /out /
COPY --from=crictl /out /
COPY --from=kubelet /out /

RUN install -m 755 -d \
        var/log/crio var/lib/crio var/lib/containers \
        /etc/kubernetes /etc/ssl/certs /run/dbus \
        /opt/cni etc/cni /var/lib/cni \
        /var/lib/kubelet /var/run/kubelet /usr/libexec/kubernetes/kubelet-plugins/volume/exec \
        /var/log/pods /var/log/containers

COPY kubelet.service /etc/systemd/system/

FROM --platform=$BUILDPLATFORM debian:11.1@sha256:e8c184b56a94db0947a9d51ec68f42ef5584442f20547fa3bd8cbd00203b2e7a AS squashfs

RUN \
        --mount=type=cache,target=/var/cache/apt \
        --mount=type=cache,target=/var/lib/apt,sharing=locked \
        set -x -e; \
        rm -f /etc/apt/apt.conf.d/docker-clean; \
        echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache; \
        apt-get update -qy; \
        apt-get install -qy --no-install-recommends \
        squashfs-tools

COPY --from=final / /rootfs

ARG KUBELET_VERSION

WORKDIR /out
RUN mksquashfs /rootfs kubelet_${KUBELET_VERSION#v}.raw

FROM --platform=$TARGETPLATFORM scratch AS final-squashfs

COPY --from=squashfs /out /
