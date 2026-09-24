FROM su3817807/ctyun:latest

USER root

# Cron 按北京时间执行
ENV TZ=Asia/Shanghai
ENV RUNNING_IN_DOCKER=true
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# apt 镜像源；官方 deb.debian.org 自带全球 CDN，国内构建传 --build-arg APT_MIRROR=mirrors.aliyun.com
ARG APT_MIRROR=deb.debian.org
RUN sed -i "s/deb.debian.org/${APT_MIRROR}/g" /etc/apt/sources.list 2>/dev/null || true && \
    sed -i "s/deb.debian.org/${APT_MIRROR}/g" /etc/apt/sources.list.d/debian.sources 2>/dev/null || true

# Chromium、中文字体、Cron 及图像处理底层库
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    chromium \
    chromium-driver \
    fonts-wqy-zenhei \
    cron \
    libgl1 \
    libglib2.0-0 \
    dos2unix \
    && rm -rf /var/lib/apt/lists/*

# Debian 12 开启 PEP 668，需 break-system-packages；国内构建传 --build-arg PIP_INDEX_URL=https://mirrors.aliyun.com/pypi/simple/
ARG PIP_INDEX_URL=https://pypi.org/simple
RUN pip3 install --no-cache-dir -i "$PIP_INDEX_URL" \
    DrissionPage==4.0.4.19 ddddocr --break-system-packages

COPY login_script.py /app/login_script.py
COPY pc_login.py /app/pc_login.py
COPY entrypoint.sh /app/entrypoint.sh

# 修复 Windows 下可能产生的 CRLF 换行符
RUN dos2unix /app/entrypoint.sh && chmod +x /app/entrypoint.sh

RUN { \
    echo "0 3,20 * * * root /usr/bin/python3 /app/login_script.py > /proc/1/fd/1 2>&1"; \
    echo "0 4,6 * * * root /usr/bin/python3 /app/pc_login.py > /proc/1/fd/1 2>&1"; \
    } > /etc/cron.d/ctyun-cron \
    && chmod 0644 /etc/cron.d/ctyun-cron \
    && crontab /etc/cron.d/ctyun-cron

# 覆盖原镜像 ENTRYPOINT，双进程启动
ENTRYPOINT ["/app/entrypoint.sh"]
