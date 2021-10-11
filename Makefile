DOCKER = docker
BUILDCACHE = /tmp/buildcache
PLATFORMS = linux/amd64

BUILD_FLAGS = \
	--platform=$(PLATFORMS) \
	--cache-to=type=local,dest=$(BUILDCACHE) \
	--cache-from=type=local,src=$(BUILDCACHE)

raw:
	$(DOCKER) buildx build $(BUILD_FLAGS) --target final-squashfs -o type=local,dest=$(PWD) .

rootfs:
	$(DOCKER) buildx build $(BUILD_FLAGS) --target final -o type=local,dest=rootfs .

install: raw
	portablectl attach --profile=trusted --now kubelet_*.raw
