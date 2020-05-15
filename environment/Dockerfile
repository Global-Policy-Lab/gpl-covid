# hash:sha256:aee499203642ec18c74e9165b33ff3b7637a764112ac85e1acd8b55460087448
FROM registry.codeocean.com/codeocean/stata:16.0-ubuntu18.04

ARG DEBIAN_FRONTEND=noninteractive

SHELL ["/bin/bash", "-c"]

COPY stata.lic /usr/local/stata/stata.lic
COPY environment.yml /tmp
COPY environment_base.yml /tmp

RUN apt-get update \
    && apt-get install -y tzdata \
    && rm -rf /var/lib/apt/lists/*
    
RUN stata 'ssc install coefplot' \
    && stata 'ssc install filelist' \
    && stata 'ssc install ftools' \
    && stata 'ssc install outreg2' \
    && stata 'ssc install reghdfe' \
    && stata 'ssc install carryforward'

ENV PATH="/opt/conda/bin:$PATH"
RUN install=Miniconda3-latest-Linux-x86_64.sh \
    && curl -O https://repo.anaconda.com/miniconda/$install \
    && bash $install -b -p /opt/conda \
    && rm $install \
    && conda config --add channels conda-forge \
    && conda config --set channel_priority strict \
    && conda update conda \
    && conda init bash \
    && source /opt/conda/etc/profile.d/conda.sh \
    && conda activate \
    && conda update --all \
    && conda env update -f /tmp/environment_base.yml \
    && conda env create -f /tmp/environment.yml \
    && conda activate gpl-covid \
    && python -m ipykernel install --user --name gpl-covid \
    && R -e 'IRkernel::installspec()' \
    && conda activate \
    && ipython -c "import ipystata; \
        from ipystata.config import config_stata; \
        config_stata('/usr/local/stata/stata-mp')" \
    && python -m stata_kernel.install \
    && jupyter labextension install jupyterlab-stata-highlight \
    && conda clean -ya
