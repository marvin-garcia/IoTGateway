WITH AnomalyDetectionStep AS
(
    SELECT
        IoTHub.IoTHub.ConnectionDeviceId AS id,
        EventEnqueuedUtcTime AS time,
        CAST(temperature AS float) AS temp,
        AnomalyDetection_SpikeAndDip(CAST(temperature AS float), 94, 240, 'spikesanddips')
            OVER(PARTITION BY id LIMIT DURATION(second, 1200)) AS SpikeAndDipScores
    FROM iothub
    WHERE temperature IS NOT NULL and ApplicationUri is NULL
)
SELECT
    id AS "iothub-connection-device-id",
    time,
    CAST(GetRecordPropertyValue(SpikeAndDipScores, 'IsAnomaly') AS bigint) as temperature_anomaly,
    CAST(GetRecordPropertyValue(SpikeAndDipScores, 'Score') AS float) AS temperature_anomaly_score
INTO temperatureanomaly
FROM AnomalyDetectionStep
