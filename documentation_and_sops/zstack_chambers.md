# Running a Z-stack microchamber experiment

This protocol describes the best way of running a Z-stack microchamber experiment. It uses GA3 to do autofocus and NIS Out Proc to automatically recenter each position using a CNN.

## 1. Creating the job

1. In the job explorer, open the VALIDATED_JOBS project and duplicate one of the jobs there into your own project. You need to choose the job depending on what you need in your experiment. The main choice is between using Triggered Experiments or ND Acquisition. Triggered Experiment is less flexible but should be faster and more robust (?). ND Acquisition lets you do more things, like use triggered illumination, assymetric stacks, etc ...

2. Open the job and change the name and description to something that makes sense for your experiment.

3. Enter your positions. Please listen to the comments and do not modify things that should not be modified.

4. Modify / double check the OCs selected for the snapshots. 

5. Modify / double check the OCs selected for the Z-stacks.

## 2. Verify the feedback microscopy part

1. Run the job until the first snapshot and zstack are acquired. Open then inside of NIS and check if they look good. 
### GA3 autofocus

1. Load the Z-stack you just acquired.
2. Open the GA3 explorer (actual path) and copy the right master recipe depending on the type of experiment you are doing (triggered vs ND acquisition).
3. Open your copied recipe and link it to the opened Z-stack. This ensures that it's correctly set up for the kind of images it's going to receive later.
4. Verify that the autofocus is working correctly by toggling "preview" and looking at the linegraph. If you see a clear peak, then it's working. If not, you might need to change the channel used or the recipe.

### NIS Out Proc recentering
1. Start WSL
2. Go to the NIS_out_proc_scripts directory and then in the directory of the script you want to launch
3. Modify the config file (corresponding to your system, WSL in this case). Make sure that all the parameters are correct.
4. Activate the towbintools micromamba environment
5. Run the script
6. Wait for the output to say "Ready", then run your job.