# Free open-source EDA toolchain for Auralis' semiconductor adapter.
FROM ubuntu:24.04
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
        verilator iverilog yosys python3 make ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN useradd -m eda
USER eda
WORKDIR /work
