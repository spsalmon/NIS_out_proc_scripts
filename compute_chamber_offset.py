import time
from pathlib import Path
from towbintools.foundation.image_handling import read_tiff_file
import torch
import numpy as np
from towbintools.deep_learning.utils.augmentation import (
    get_prediction_augmentation_from_model,
)
from towbintools.deep_learning.deep_learning_tools import (
    load_segmentation_model_from_checkpoint,
)
from towbintools.foundation import image_handling
from towbintools.deep_learning.utils.util import get_closest_upper_multiple
from towbintools.foundation.binary_image import get_biggest_object
from skimage.measure import centroid
    
SYNC_NOT_READY = "0"
SYNC_READY = "1"
SYNC_FINISHED = "2"
SYNC_CANCEL = "3"
PIXELSIZE = 0.2167

POLL_INTERVAL = 0.25
INPUT_IMAGE = 'C:/NIS_out_proc/img.tif'
SYNC_FILE = 'C:/NIS_out_proc/sync.txt'
OUT_PARAMS = 'C:/NIS_out_proc/out_params.txt'

def read_text(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return f.read().strip()
    except FileNotFoundError:
        return ""
    except Exception:
        return ""


def write_text(path, text):
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
model_path = '//izbkingston/towbin.data/shared/spsalmon/towbinlab_segmentation_database/models/chamber_segmentation/best_light.ckpt'
model = load_segmentation_model_from_checkpoint(model_path).to(device)
model.eval()
transform = get_prediction_augmentation_from_model(model)

def segment_chamber(image):
    global model, transform
    with torch.no_grad():
        image = transform({"image": image})['image'] # type: ignore
        
        original_shape = image.shape
        
        dim_x = get_closest_upper_multiple(image.shape[-2], 32)
        dim_y = get_closest_upper_multiple(image.shape[-1], 32)
        image = image_handling.pad_to_dim_equally(image, dim_x, dim_y) # type: ignore
        image = image[np.newaxis, np.newaxis, ...]
        image = torch.tensor(image).to(device)
        prediction = model(image)
        prediction = prediction.cpu().numpy() > 0.9
        prediction = np.squeeze(prediction)
        
        prediction = image_handling.crop_to_dim_equally(prediction, original_shape[-2], original_shape[-1])
    
        return prediction.astype(np.uint8)

def compute_offset(mask, pixelsize):
    mask = get_biggest_object(mask)
    mask_center = centroid(mask)

    frame_center = np.array(mask.shape) // 2 

    offset = (mask_center - frame_center) * pixelsize

    print(f'Offset : {offset}')

    return offset

def save_output_params(path, offset):
    lines = [
        f"{offset[1]:.3f}",
        f"{offset[0]:.3f}",
    ]
    write_text(path, "\n".join(lines) + "\n")

def process_once(input_image, out_params, pixelsize):
    img = read_tiff_file(input_image, channels_to_keep=[0])
    mask = segment_chamber(img)
    offset = compute_offset(mask, pixelsize)

    if out_params:
        save_output_params(out_params, offset)

def main():
    last_state = None
    print('Running ! Waiting for NIS ...')
    while True:
        state = read_text(SYNC_FILE)

        if state == SYNC_CANCEL:
            break

        if state == SYNC_READY and last_state != SYNC_READY:
            try:
                process_once(
                    INPUT_IMAGE,
                    OUT_PARAMS,
                    PIXELSIZE
                )
                write_text(SYNC_FILE, SYNC_FINISHED)
            except Exception:
                write_text(SYNC_FILE, SYNC_CANCEL)

        last_state = state
        time.sleep(POLL_INTERVAL)

if __name__ == "__main__":
    main()