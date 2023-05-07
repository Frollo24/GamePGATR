using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class TestDeathBehaviour : MonoBehaviour
{
    public Renderer meshRenderer;
    public Material explodeMaterial;

    private void Update()
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
        }
    }
}
