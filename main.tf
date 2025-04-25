# Configure AWS Provider
provider "aws" {
  region = "us-east-1"
}

# --- MediaLive Input (RTMP) ---
resource "aws_medialive_input" "obs_input" {
  name      = "obs-rtmp-input"
  type      = "RTMP_PUSH"
  
  # Optional: Input security group (if using authentication)
  input_security_groups = [aws_medialive_input_security_group.input_sg.id]
}

# --- MediaLive Channel ---
resource "aws_medialive_channel" "stream_channel" {
  name          = "transcoded-stream"
  channel_class = "STANDARD"  # Single-pipeline for cost savings

  # Attach the input
  input_specification {
    codec          = "AVC"
    input_resolution = "HD"
    maximum_bitrate = "MAX_20_MBPS"
  }

  input_attachments {
    input_attachment_name = "obs-input"
    input_id             = aws_medialive_input.obs_input.id
  }

  # Video encode settings (1080p60)
  encoder_settings {
    video_descriptions {
      name  = "video-1080p60"
      width = 1920
      height = 1080
      codec_settings {
        h264_settings {
          bitrate             = 6000000  # 6 Mbps
          rate_control_mode   = "CBR"
          framerate_denominator = 1
          framerate_numerator   = 60
          gop_size            = 60
          profile             = "HIGH"
        }
      }
    }

    # Audio encode settings
    audio_descriptions {
      name  = "audio-stereo"
      codec_settings {
        aac_settings {
          bitrate    = 160000  # 160 kbps
          sample_rate = 48000
        }
      }
    }

    # Output Group (MediaPackage)
    output_groups {
      output_group_settings {
        hls_group_settings {
          destination {
            destination_ref_id = "mediapackage-destination"
          }
        }
      }

      outputs {
        output_name = "1080p60-output"
        video_description_name = "video-1080p60"
        audio_description_names = ["audio-stereo"]
        output_settings {
          hls_output_settings {
            segment_modifier = "$dt$"
          }
        }
      }
    }
  }
}

# --- MediaPackage Channel ---
resource "aws_mediapackage_channel" "hls_channel" {
  id = "translated-stream-hls"
}

# --- MediaPackage HLS Endpoint ---
resource "aws_mediapackage_channel" "hls_endpoint" {
  channel_id = aws_mediapackage_channel.hls_channel.id

  hls_ingest {
    ingest_endpoints {
      password = "super-secret-password"  # Change this!
      username = "aws-terraform"
      url      = "https://input-${aws_mediapackage_channel.hls_channel.id}.mediapackage.amazonaws.com/in/v1/abcdef123456/ingest"
    }
  }
}

# --- IAM for MediaLive to MediaPackage ---
resource "aws_iam_role" "medialive_role" {
  name = "medialive-mediapackage-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Action = "sts:AssumeRole",
      Effect = "Allow",
      Principal = {
        Service = "medialive.amazonaws.com"
      }
    }]
  })
}

# --- Outputs ---
output "medialive_input_url" {
  value = aws_medialive_input.obs_input.destinations[0].url
}

output "mediapackage_hls_url" {
  value = aws_mediapackage_channel.hls_channel.hls_ingest.ingest_endpoints[0].url
}
