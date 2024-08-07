# Copyright 2020 Unibg Seclab (https://seclab.unibg.it)
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

FROM apache/spark-py:v3.4.0

USER root

# install application requirements
COPY requirements.txt /tmp/
RUN ["pip", "install", "--upgrade", "pip"]
RUN ["pip", "install", "--requirement", "/tmp/requirements.txt"]

# import files
RUN mkdir "/mondrian"
COPY anonymize.py /mondrian/
COPY mondrian.zip /mondrian/

# [history server] overwrite default directory containing application event logs
# RUN echo "spark.history.fs.logDirectory /data/spark-events" >> $SPARK_HOME/conf/spark-defaults.conf