using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class Spawner : MonoBehaviour
{

    [SerializeField] private List<Transform> spawnPoints = new List<Transform>();
    [SerializeField] private GameObject prefab;
    // Start is called before the first frame update
    private float nextActionTime = 0.0f;
    public float period = 3.0f;

    // Update is called once per frame
    void Update()
    {
        if (Time.time > nextActionTime)
        {

            nextActionTime = Time.time + period;

            Vector3 spawnPnt = spawnPoints[UnityEngine.Random.Range(0, spawnPoints.Count)].position;

            Quaternion rotation = Quaternion.LookRotation(-spawnPnt, Vector3.up);

            Instantiate(prefab, spawnPnt, rotation);
        }
    }
}
