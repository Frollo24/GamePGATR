using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class ShooterBehaviour : MonoBehaviour
{
    public LayerMask enemiesLayer;

    private void Update()
    {
        if (Input.GetButtonDown("Fire1") && Physics.Raycast(transform.position, transform.forward, out RaycastHit hit, 50f, enemiesLayer))
        {
            // TODO: call enemy death effects
            Destroy(hit.transform.gameObject);
        }
    }
}
