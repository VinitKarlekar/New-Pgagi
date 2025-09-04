# CI/CD Overlap Fix - Terraform and GitHub Actions

## Summary
Fixed the overlap between Terraform infrastructure provisioning and GitHub Actions CI/CD pipeline by reordering the workflow steps to ensure ECR repositories exist before pushing Docker images.

## Changes Made
- [x] Moved Terraform apply from deploy job to build job (conditional on main branch)
- [x] Removed redundant Terraform steps from deploy job
- [x] Ensured infrastructure is provisioned before image builds

## Workflow Order Now
1. Test (runs tests)
2. Build (for main: terraform apply -> build & push images; for others: build & push images)
3. Deploy (update ECS services)

## Benefits
- Eliminates "repository does not exist" error after terraform destroy
- Prevents "resource already exists" errors during terraform apply
- Proper separation of infrastructure and application deployment
- Idempotent for multiple runs on main branch

## Next Steps
- Test the updated workflow on a push to main branch
- Monitor for any issues with terraform state or resource conflicts
- Consider adding terraform destroy to a separate manual workflow if needed
