This repo is for storing and synchronizing scripts used through the "out proc" part of JOBS to do some feedback microscopy.

# Installation

1. Follow the WSL should already be installed so you do not need admin rights, just run :

```PowerShell
wsl --install -d Ubuntu
```

To install Ubuntu in your session. To access WSL, run :

```PowerShell
wsl
```

Or look for WSL in the Windows search bar.

Then proceed with the [instructions for installing the pipeline on Linux](https://spsalmon.github.io/towbintools_pipeline/installation/#linux). 

2. Clone this repository

```bash
cd
git clone https://github.com/spsalmon/NIS_out_proc_scripts.git
```

3. Run the setup script that will mount towbin.data permanently so you can access the cluster (for models, images, etc.)

```bash
cd ~/NIS_out_proc_scripts
bash setup.sh
```

# Running a script

1. Update the scripts

```bash
cd NIS_out_proc_scripts
git pull
```

2. Activate the towbintools micromamba environment

```bash
micromamba activate towbintools
```

3. Go in the script's folder, and link the proper configuration file, example:

```bash
cd compute_chamber_offset
python compute_chamber_offset.py -c /path/to/config
```

4. Wait for the script to say it's ready before starting your job