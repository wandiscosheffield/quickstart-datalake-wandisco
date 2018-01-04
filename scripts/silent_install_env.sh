# User which will run Fusion services. This should match the user who runs
# the hdfs service. For example, FUSIONUI_USER=hdfs
FUSIONUI_USER=hadoop

# Group of the user which will run Fusion services. The specified group must
# be one that FUSIONUI_USER is in.
FUSIONUI_GROUP=hadoop

# Backend choice you wish to use for this installation
FUSIONUI_FUSION_BACKEND_CHOICE=asf-2.7.0

# UI username
# REQUIRED for installation with no cluster manager
# Ignored for installation with a cluster manager
FUSIONUI_INTERNALLY_MANAGED_USERNAME=admin

# UI password
# REQUIRED for installation with no cluster manager
# Ignored for installation with a cluster manager
FUSIONUI_INTERNALLY_MANAGED_PASSWORD=admin