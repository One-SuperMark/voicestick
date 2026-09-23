#pragma once

#include <stdint.h>
#include "esp_err.h"

esp_err_t audio_pipeline_init(void);
esp_err_t audio_pipeline_start(uint32_t session_id);
esp_err_t audio_pipeline_stop(void);
/* A short speaker cue used only when the BLE transport is ready for input. */
esp_err_t audio_pipeline_play_ready_tone(void);
uint32_t audio_pipeline_session_id(void);
