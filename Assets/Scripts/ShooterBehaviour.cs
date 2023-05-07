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

            MovingAgent target = hit.transform.gameObject.GetComponent<MovingAgent>();

            if (target != null && !target.explode) 
            {
                target.Explode();
            }
        }
    }
}
