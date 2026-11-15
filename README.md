# misc
个人杂项项目整合

## chroot-utils

一个 chroot 容器管理脚本：建容器、进出、登记绑定挂载、删容器。只用 bash 和 util-linux，不需要 docker。

```
./install.sh              # 装到 ~/.local/bin/chroot-utils（也可 PREFIX=/opt/x ./install.sh）
./install.sh --uninstall

chroot-utils --create arch                       # 下载 Arch bootstrap 建容器（国内镜像）
chroot-utils --create arch --upgrade             # 建完顺手 pacman -Syu
chroot-utils --create arch ./bootstrap.tar.zst   # 用本地包
chroot-utils --start arch                        # 进容器，默认 /bin/bash
chroot-utils --start arch -- /bin/zsh
chroot-utils --mount arch /home/user /mnt        # 登记绑定挂载，下次 --start 生效
chroot-utils --umount arch /mnt
chroot-utils --mounts arch
chroot-utils --rm arch                           # 删容器，有挂载或有进程就拒绝
chroot-utils --cleanup arch                      # 只拆残留挂载，不删文件
chroot-utils --list
```

容器根目录在 `/opt/rootfs/<名字>/`，可用 `CHROOT_UTILS_ROOTFS` 改。

### 为什么不像别的脚本那样往容器里 bind mount

旧做法是在宿主机的挂载命名空间里往 rootfs 里挂 proc/sys/dev 和用户目录，有两个必然会踩的坑：

- 容器已经在后台跑着，再执行一次 `--start` 会往同一个挂载点上叠一层；后启动的那次退出时执行 umount，拆掉的是前一个会话的挂载，正在跑的容器当场坏掉。
- 用户 bind 过宿主机目录、挂载还没拆干净时执行 `--rm`，`rm -rf` 会顺着挂载点把宿主机那个目录里的东西删掉。

所以这个脚本每次进入都用 `unshare -m` 开一个私有挂载命名空间，所有挂载都只在里面存在，退出时内核连整棵树一起丢弃。宿主机挂载表里从头到尾不会出现 rootfs 路径，因此重复启动、后台多开会话、删容器都不会互相破坏。`--mount` 也因此只写清单（`/var/lib/chroot-utils/<名字>.mounts`），在下次 `--start` 的命名空间里生效。

会话里实际挂进去的东西，全部只在这个命名空间内：

| 位置 | 来源 |
| --- | --- |
| `/proc` | 新 proc 实例，不允许时退回 rbind 宿主 |
| `/sys`、`/dev` | rbind 宿主并 make-rslave，不往回传播 |
| `/run` | 空 tmpfs，别让容器往镜像里写运行时文件 |
| `/etc/resolv.conf` | 宿主那份只读 bind；容器内是符号链接的不动 |
| `--mount` 登记的目录 | 宿主目录 bind |

locale 也做了处理：宿主带进来的 `LC_ALL`/`LANG` 不会原样传进去（一个没生成 locale 的容器只会刷一串 `cannot change locale` 警告），默认用 `LANG=C.UTF-8`；要别的就 `CHROOT_UTILS_LANG=zh_CN.UTF-8`（容器里得先生成对应 locale）。

### Arch 容器

`--create` 认到包里带 `usr/bin/pacman` 就把教程里那些步骤一次做完：

1. `/etc/pacman.d/mirrorlist` 换成本文的国内源（原文件存为 `mirrorlist.dist`）。
2. 注释掉 `/etc/pacman.conf` 里的 `CheckSpace`。
3. 进容器跑 `pacman-key --init` 和 `pacman-key --populate archlinux` 建好密钥库（离线，密钥随包发）。
4. 启用并生成 `en_US.UTF-8` locale。
5. 问一句要不要顺手 `pacman -Syu`（`--upgrade` 直接升，非交互环境下不问也不升）。

前 4 步都离线，任一步失败只警告并给出容器内手动补的命令，不会留下半成品容器。

`CheckSpace`：chroot 里 pacman 算不出 cachedir 的挂载点，`pacman -Syu` 会在下载完成后报

```
error: could not determine cachedir mount point /var/cache/pacman/pkg/download-XXXXXX
error: failed to commit transaction (not enough free disk space)
```

并把整个事务中止。手动关掉就是 `pacman.conf` 的 `[options]` 段里把 `CheckSpace` 注释掉。

keyring：bootstrap 包的密钥库是空的，不 populate 的话每个包都会报

```
error: libbpf: signature from "Levente Polyak <anthraxx@archlinux.org>" is unknown trust
:: File /var/cache/pacman/pkg/libbpf-...pkg.tar.zst is corrupted (invalid or corrupted package (PGP signature)).
error: failed to commit transaction (invalid or corrupted package (PGP signature))
```

注意它会把签名验不过的包说成"corrupted"，其实包是好的。修法是进容器跑

```
pacman-key --init
pacman-key --populate archlinux
```

然后重跑 `pacman -Syu`。中途那些 `Do you want to delete it? [Y/n]` 建议答 `n`，包留在
`/var/cache/pacman/pkg/` 里，keyring 修好后直接复用，不用重新下载。

老容器没被 `--create` 处理过的，在宿主上补：

```
sed -i 's/^CheckSpace/#CheckSpace/' /opt/rootfs/arch/etc/pacman.conf
chroot-utils --start arch -- /usr/bin/pacman-key --init
chroot-utils --start arch -- /usr/bin/pacman-key --populate archlinux
```
