
using Microsoft.AspNetCore.Identity;
using System.Collections.Generic;

namespace MvcMusicStore.Models
{
    // You can add profile data for the user by adding more properties to your ApplicationUser class
    public class ApplicationUser : IdentityUser
    {
        internal HashSet<string> RoleIds { get; private set; } = new();

        internal ApplicationUser Copy()
        {
            var copy = (ApplicationUser)MemberwiseClone();
            copy.RoleIds = new HashSet<string>(RoleIds);
            return copy;
        }
    }
}