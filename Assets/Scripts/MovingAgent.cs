using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.AI;


public class MovingAgent : MonoBehaviour
{

    public NavMeshAgent agent;

    public Renderer meshRenderer;
    public Material explodeMaterial;
    private float distanceToTarget = 1.0f;

    // Update is called once per frame
    void Update()
    {
        if (Input.GetKeyDown(KeyCode.T))
        {
            var materials = meshRenderer.materials;
            for (int i = 0; i < materials.Length; i++)
            {
                materials[i] = explodeMaterial;
                materials[i].SetFloat("_StartTime", Time.time);
            }
            meshRenderer.materials = materials;
            gameObject.GetComponent<Animator>().enabled = false;
            agent.isStopped = true;
        }

        agent.SetDestination(Vector3.zero);

        if ((Vector3.Distance(transform.position, Vector3.zero)) < distanceToTarget) //done with path
        {
            Destroy(gameObject);
        }
    }
}
