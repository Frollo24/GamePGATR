using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class TerrainFlattener : MonoBehaviour
{
    public Texture2D falloffMap;
    public MeshRenderer terrain;

    private void Start()
    {
        terrain.material.SetTexture("_FalloffMap", falloffMap);
    }
}
